//
//  ApplyDeferredUploads.swift
//  Server
//
//  Created by Christopher G Prince on 7/18/20.
//

import Foundation
import ServerAccount
import ChangeResolvers
import ServerShared
import LoggerAPI

// Each DeferredUpload corresponds to one or more Upload record.
/* Here's the algorithm:
    0) Open the database transaction.
    1) let allUploads = all of the Upload records corresponding to these DeferredUpload's.
    2) let fileUUIDs = the set of unique fileUUID's within allUploads.
    3) let uploads(fileUUID) be the set of Upload's for a given fileUUID within fileUUIDs, i.e., within allUploads.
    4) for fileUUID in fileUUIDs {
         let uploadsForFileUUID = uploads(fileUUID)
         Get the change resolver for this fileUUID from the FileIndex
         Read the file indicated by fileUUID from cloud storage.
         for upload in uploadsForFileUUID {
           Apply the change in upload to the file data using the change resolver.
         }
         Write the file data for the updated file back to cloud storage.
       }
    5) Do the update of the FileIndex based on these DeferredUpload records.
    6) Remove these DeferredUpload from the database.
    7) End the database transaction.
 */

// Process a group of deferred uploads
// All deferred uploads given must have the sharingGroupUUID given.
// If a fileGroupUUID is given, then all DeferredUploads given must have the fileGroupUUID given. The file group must be in the given sharing group. In this case, all updates in all of the DeferredUpload's are processed as a unit-- in one database transaction.
// If no fileGroupUUID is given, then all DeferredUploads must have a nil fileGroupUUID. In this case, changes for each fileUUID are processed as a unit-- in separate database transaction's.
// Call the `run` method to kick this off. Once this succeeds, it removes the DeferredUpload's. It does the datatabase operations within a transaction.
// NOTE: Currently this statement of consistency applies at the database level, but not at the file level. If this fails mid-way through processing, new file versions may be present. We need to put in some code to deal with a restart which itself doesn't fail if the a new file version is present. Perhaps overwrite it?
class ApplyDeferredUploads {
    enum Errors: Error {
        case notAllInGroupHaveSameFileGroupUUID
        case notAllInGroupHaveNilFileGroupUUID
        case notAllDeferredUploadsHaveSameSharingGroupUUID
        case deferredUploadIds
        case couldNotGetAllUploads
        case couldNotGetFileUUIDs
        case failedRemovingDeferredUpload
        case couldNotLookupFileUUID
        case couldNotGetOwningUserCreds
        case couldNotConvertToCloudStorage
        case couldNotLookupResolverName
        case couldNotLookupResolver
        case failedStartingTransaction
        case couldNotCommit
        case failedSetupForApplyChangesToSingleFile(String)
        case unknownResolverType
        case couldNotGetDeviceUUID
        case couldNotGetPriorFileVersion
        case failedRemovingUploadRow
        case failedUpdatingFileIndex
    }
    
    let sharingGroupUUID: String
    let deferredUploads: [DeferredUpload]
    let db: Database
    let allUploads: [Upload]
    let fileIndexRepo: FileIndexRepository
    let accountManager: AccountManager
    let resolverManager: ChangeResolverManager
    let fileUUIDs: [String]
    let uploadRepo:UploadRepository
    let deferredUploadRepo:DeferredUploadRepository
    let haveFileGroupUUID: Bool
    var fileDeletions = [FileDeletion]()
    
    init?(sharingGroupUUID: String, fileGroupUUID: String? = nil, deferredUploads: [DeferredUpload], accountManager: AccountManager, resolverManager: ChangeResolverManager, db: Database) throws {
        self.sharingGroupUUID = sharingGroupUUID
        self.deferredUploads = deferredUploads
        self.db = db
        self.accountManager = accountManager
        self.resolverManager = resolverManager
        self.fileIndexRepo = FileIndexRepository(db)
        self.uploadRepo = UploadRepository(db)
        self.deferredUploadRepo = DeferredUploadRepository(db)
        
        guard deferredUploads.count > 0 else {
            return nil
        }
        
        if let fileGroupUUID = fileGroupUUID {
            guard (deferredUploads.filter {$0.fileGroupUUID == fileGroupUUID}).count == deferredUploads.count else {
                throw Errors.notAllInGroupHaveSameFileGroupUUID
            }
            haveFileGroupUUID = true
        }
        else {
            guard (deferredUploads.compactMap {$0.fileGroupUUID}).count == 0 else {
                throw Errors.notAllInGroupHaveNilFileGroupUUID
            }
            haveFileGroupUUID = false
        }
        
        guard (deferredUploads.filter {$0.sharingGroupUUID == sharingGroupUUID}).count == deferredUploads.count else {
            throw Errors.notAllDeferredUploadsHaveSameSharingGroupUUID
        }
        
        let deferredUploadIds = deferredUploads.compactMap{$0.deferredUploadId}
        guard deferredUploads.count == deferredUploadIds.count else {
            throw Errors.deferredUploadIds
        }
        
        guard let allUploads = UploadRepository(db).select(forDeferredUploadIds: deferredUploadIds) else {
            throw Errors.couldNotGetAllUploads
        }
        self.allUploads = allUploads
        
        let fileUUIDs = allUploads.compactMap{$0.fileUUID}
        guard fileUUIDs.count == allUploads.count else {
            throw Errors.couldNotGetFileUUIDs
        }
        
        // Now that we have the fileUUIDs, reduce to just the unique fileUUID's.
        self.fileUUIDs = Array(Set<String>(fileUUIDs))
    }
    
    func cleanup(completion: @escaping (Error?)->()) {
        for deferredUpload in deferredUploads {
            let key = DeferredUploadRepository.LookupKey.deferredUploadId(deferredUpload.deferredUploadId)
            let result = deferredUploadRepo.retry {
                return self.deferredUploadRepo.remove(key: key)
            }
            guard case .removed(numberRows: let numberRows) = result,
                numberRows == 1 else {
                completion(Errors.failedRemovingDeferredUpload)
                return
            }
        }
        
        FileDeletion.apply(deletions: fileDeletions) { _ in
            completion(nil)
        }
    }
    
    func uploads(fileUUID: String) -> [Upload] {
        return allUploads.filter{$0.fileUUID == fileUUID}
    }

    func getFileIndex(forFileUUID fileUUID: String) throws -> FileIndex {
        let key = FileIndexRepository.LookupKey.primaryKeys(sharingGroupUUID: sharingGroupUUID, fileUUID: fileUUID)
        let result = fileIndexRepo.lookup(key: key, modelInit: FileIndex.init)
        guard case .found(let model) = result,
            let fileIndex = model as? FileIndex else {
            throw Errors.couldNotLookupFileUUID
        }
        
        return fileIndex
    }
    
    func getCloudStorage(forFileUUID fileUUID: String, usingFileIndex fileIndex: FileIndex) throws -> (Account, CloudStorage) {
        guard let owningUserCreds = FileController.getCreds(forUserId: fileIndex.userId, from: db, accountManager: accountManager) else {
            throw Errors.couldNotGetOwningUserCreds
        }
        
        guard let cloudStorage = owningUserCreds as? CloudStorage else {
            throw Errors.couldNotConvertToCloudStorage
        }
        
        return (owningUserCreds, cloudStorage)
    }
    
    func changeResolver(forFileUUID fileUUID: String, usingFileIndex fileIndex: FileIndex) throws -> ChangeResolver.Type {
        guard let changeResolverName = fileIndex.changeResolverName else {
            Log.error("couldNotLookupResolverName: \(String(describing: fileIndex.changeResolverName))")
            throw Errors.couldNotLookupResolverName
        }
        
        guard let resolverType = resolverManager.getResolverType(changeResolverName) else {
            Log.error("couldNotLookupResolver")
            throw Errors.couldNotLookupResolver
        }
        
        return resolverType
    }
    
    // Have a fileGroupUUID. Commit changes after entire file group is processed.
    private func runWithFileGroupUUID(completion: @escaping (Error?)->()) {
        guard db.startTransaction() else {
            completion(Errors.failedStartingTransaction)
            return
        }
        
        func apply(fileUUID: String, completion: @escaping (Swift.Result<Void, Error>) -> ()) {
            Log.debug("applyChangesToSingleFile: \(fileUUID)")

            applyChangesToSingleFile(fileUUID: fileUUID) { error in
                if let error = error {
                    completion(.failure(error))
                    return
                }
                
                completion(.success(()))
            }
        }
        
        let result = fileUUIDs.synchronouslyRun(apply: apply)
        switch result {
        case .success:
            guard self.db.commit() else {
                completion(Errors.couldNotCommit)
                return
            }
            
            Log.info("About to start cleanup.")
            self.cleanup(completion: completion)
            
        case .failure(let error):
            _ = self.db.rollback()
            completion(error)
        }
    }
    
    // Have no fileGroupUUID. Commit changes after each file is processed.
    private func runWithoutFileGroupUUID(completion: @escaping (Error?)->()) {
        func apply(fileUUID: String, completion: @escaping (Swift.Result<Void, Error>) -> ()) {
            guard db.startTransaction() else {
                completion(.failure(Errors.failedStartingTransaction))
                return
            }
        
            Log.debug("applyChangesToSingleFile: \(fileUUID)")

            applyChangesToSingleFile(fileUUID: fileUUID) { error in
                if let error = error {
                    _ = self.db.rollback()
                    completion(.failure(error))
                    return
                }
                
                guard self.db.commit() else {
                    completion(.failure(Errors.couldNotCommit))
                    return
                }
            
                completion(.success(()))
            }
        }
        
        let result = fileUUIDs.synchronouslyRun(apply: apply)
        switch result {
        case .success:
            Log.info("About to start cleanup.")
            // TODO: Could cleanup after each successful commit. But would have to remove just those DeferredUpload's dealt with so far. And remove any FileDeletion's completed.
            self.cleanup(completion: completion)
            
        case .failure(let error):
            completion(error)
        }
    }
    
    // Apply changes to all fileUUIDs. This deals with database transactions.
    func run(completion: @escaping (Error?)->()) {
        if haveFileGroupUUID {
            runWithFileGroupUUID(completion: completion)
        }
        else {
            runWithoutFileGroupUUID(completion: completion)
        }
    }
    
    func applyChangesToSingleFile(fileUUID: String, completion: @escaping (Error?)->()) {
        let uploadsForFileUUID = uploads(fileUUID: fileUUID)
        
        guard let fileIndex = try? getFileIndex(forFileUUID: fileUUID) else {
            completion(Errors.failedSetupForApplyChangesToSingleFile("FileIndex"))
            return
        }
        
        guard let resolver = try? changeResolver(forFileUUID: fileUUID, usingFileIndex: fileIndex) else {
            completion(Errors.failedSetupForApplyChangesToSingleFile("Resolver"))
            return
        }
        
        guard let (owningCreds, cloudStorage) = try? getCloudStorage(forFileUUID: fileUUID, usingFileIndex: fileIndex) else {
            completion(Errors.failedSetupForApplyChangesToSingleFile("getCloudStorage"))
            return
        }
        
        let options = CloudStorageFileNameOptions(cloudFolderName: owningCreds.cloudFolderName, mimeType: fileIndex.mimeType)
        
        guard let deviceUUID = fileIndex.deviceUUID else {
            completion(Errors.couldNotGetDeviceUUID)
            return
        }
        
        guard let priorFileVersion = fileIndex.fileVersion else {
            completion(Errors.couldNotGetPriorFileVersion)
            return
        }
        
        resolver.apply(changes: uploadsForFileUUID, toFileUUID: fileUUID, currentFileVersion: priorFileVersion, deviceUUID: deviceUUID, cloudStorage: cloudStorage, options: options) { result in
            switch result {
            case .failure(let error):
                completion(error)
                
            case .success(let applyResult):
                let updateSuccess = self.fileIndexRepo.update(indexId: fileIndex.fileIndexId, with: [
                    FileIndex.lastUploadedCheckSumKey: .string(applyResult.checkSum),
                    FileIndex.fileVersionKey: .int32(applyResult.newFileVersion),
                    FileIndex.updateDateKey: .dateTime(Date())
                 ])
                
                guard updateSuccess else {
                    completion(Errors.failedUpdatingFileIndex)
                    return
                }
                
                // Remove Upload records from db (uploadsForFileUUID)
                for upload in uploadsForFileUUID {
                    let key = UploadRepository.LookupKey.uploadId(upload.uploadId)
                    let result = self.uploadRepo.retry {
                        return self.uploadRepo.remove(key: key)
                    }
                    
                    guard case .removed(numberRows: let numberRows) = result,
                        numberRows == 1 else {
                        completion(Errors.failedRemovingUploadRow)
                        return
                    }
                }
                
                // Don't do deletions yet. The overall operations can't be repeated if the original files are gone.
                let currentCloudFileName = Filename.inCloud(deviceUUID: deviceUUID, fileUUID: fileUUID, mimeType: options.mimeType, fileVersion: priorFileVersion)
                let deletion = FileDeletion(cloudStorage: cloudStorage, cloudFileName: currentCloudFileName, options: options)
                self.fileDeletions += [deletion]
                
                completion(nil)
            }
        }
    }
}
