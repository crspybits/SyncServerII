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
        case couldNotCleanupDeferredUploads
        case couldNotUpdateDeferredUploads
    }
    
    let sharingGroupUUID: String
    var deferredUploads: [DeferredUpload]
    let db: Database
    let allUploads: [Upload]
    let fileIndexRepo: FileIndexRepository
    let userRepo: UserRepository
    let services: UploaderServices
    let fileUUIDs: [String]
    let uploadRepo:UploadRepository
    let deferredUploadRepo:DeferredUploadRepository
    let haveFileGroupUUID: Bool
    var fileDeletions = [FileDeletion]()
    static let debugAlloc = DebugAlloc(name: "ApplyDeferredUploads")

    init?(sharingGroupUUID: String, fileGroupUUID: String? = nil, deferredUploads: [DeferredUpload], services: UploaderServices, db: Database) throws {
        self.sharingGroupUUID = sharingGroupUUID
        self.deferredUploads = deferredUploads
        self.db = db
        self.services = services
        self.fileIndexRepo = FileIndexRepository(db)
        self.uploadRepo = UploadRepository(db)
        self.deferredUploadRepo = DeferredUploadRepository(db)
        self.userRepo = UserRepository(db)
        
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
        
        guard let allUploads = uploadRepo.select(forDeferredUploadIds: deferredUploadIds) else {
            throw Errors.couldNotGetAllUploads
        }
        self.allUploads = allUploads
        
        let fileUUIDs = allUploads.compactMap{$0.fileUUID}
        guard fileUUIDs.count == allUploads.count else {
            throw Errors.couldNotGetFileUUIDs
        }
        
        // Now that we have the fileUUIDs, reduce to just the unique fileUUID's.
        self.fileUUIDs = Array(Set<String>(fileUUIDs))
        
        Self.debugAlloc.create()
    }
    
    deinit {
        Log.debug("ApplyDeferredUploads: deinit")
        Self.debugAlloc.destroy()
    }
    
    func cleanupDeferredUploads(deferredUploads: [DeferredUpload]) -> Bool {
        // TODO/DeferredUpload: Test the status change.
        for deferredUpload in deferredUploads {
            guard deferredUploadRepo.update(indexId: deferredUpload.deferredUploadId, with: [DeferredUpload.statusKey: .string(DeferredUploadStatus.completed.rawValue)]) else {
                Log.error("Could not update DeferredUpload")
                return false
            }
            
            // Remove the DeferredUpload from the array so we don't update them multiple times.
            self.deferredUploads.removeAll { $0.deferredUploadId == deferredUpload.deferredUploadId }
        }
        
        return true
    }
    
    func cleanupDeletions(completion: @escaping (Error?)->()) {
        if let error = FileDeletion.apply(deletions: fileDeletions), error.count > 0 {
            completion(error[0])
        }
        else {
            completion(nil)
        }
    }
    
    func uploads(fileUUID: String) -> [Upload] {
        return allUploads.filter{$0.fileUUID == fileUUID}
    }
    
    func changeResolver(forFileUUID fileUUID: String, usingFileIndex fileIndex: FileIndex) throws -> ChangeResolver.Type {
        guard let changeResolverName = fileIndex.changeResolverName else {
            Log.error("couldNotLookupResolverName: \(String(describing: fileIndex.changeResolverName))")
            throw Errors.couldNotLookupResolverName
        }
        
        guard let resolverType = services.changeResolverManager.getResolverType(changeResolverName) else {
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

            applyChangesToSingleFile(fileUUID: fileUUID) { result in
                switch result {
                case .success:
                    break
                case .failure(let error):
                    completion(.failure(error))
                    return
                }
                
                completion(.success(()))
            }
        }
        
        let (_, errors) = fileUUIDs.synchronouslyRun(apply: apply)
        
        guard errors.count == 0 else {
            _ = self.db.rollback()
            completion(errors[0])
            return
        }

        guard self.cleanupDeferredUploads(deferredUploads: deferredUploads) else {
            completion(Errors.couldNotCleanupDeferredUploads)
            return
        }

        guard self.db.commit() else {
            completion(Errors.couldNotCommit)
            return
        }
        
        Log.info("About to start deletions cleanup.")
        self.cleanupDeletions(completion: completion)
    }
    
    // Have no fileGroupUUID. Commit changes after each file is processed.
    private func runWithoutFileGroupUUID(completion: @escaping (Error?)->()) {
        func apply(fileUUID: String, completion: @escaping (Swift.Result<Void, Error>) -> ()) {
            guard db.startTransaction() else {
                completion(.failure(Errors.failedStartingTransaction))
                return
            }
        
            Log.debug("applyChangesToSingleFile: \(fileUUID)")

            applyChangesToSingleFile(fileUUID: fileUUID) { [weak self] result in
                guard let self = self else { return }
                switch result {
                case .failure(let error):
                    _ = self.db.rollback()
                    completion(.failure(error))
                    return
                    
                case .success(let uploadsForFileUUID):
                    let deferredUploadIds = Set<Int64>(uploadsForFileUUID.compactMap {$0.deferredUploadId})
                    let deferredUploadsToRemove = self.deferredUploads.filter {deferredUploadIds.contains($0.deferredUploadId) }
                    guard self.cleanupDeferredUploads(deferredUploads: deferredUploadsToRemove) else {
                        _ = self.db.rollback()
                        completion(.failure(Errors.couldNotCleanupDeferredUploads))
                        return
                    }
                }
                
                guard self.db.commit() else {
                    completion(.failure(Errors.couldNotCommit))
                    return
                }
            
                completion(.success(()))
            }
        }
        
        let (_, errors) = fileUUIDs.synchronouslyRun(apply: apply)
        guard errors.count == 0 else {
            completion(errors[0])
            return
        }

        Log.info("About to start deletion cleanup.")
        // TODO: Could cleanup after each successful commit. But would have to remove just those DeferredUpload's dealt with so far. And remove any FileDeletion's completed.
        self.cleanupDeletions(completion: completion)
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
    
    // Success result is uploadsForFileUUID. Also removes all uploads for the fileUUID.
    func applyChangesToSingleFile(fileUUID: String, completion: @escaping (Swift.Result<[Upload], Error>)->()) {
        let uploadsForFileUUID = uploads(fileUUID: fileUUID)
        
        guard let fileIndex = try? fileIndexRepo.getFileIndex(forFileUUID: fileUUID, sharingGroupUUID: sharingGroupUUID) else {
            completion(.failure(Errors.failedSetupForApplyChangesToSingleFile("FileIndex")))
            return
        }
        
        guard let resolver = try? changeResolver(forFileUUID: fileUUID, usingFileIndex: fileIndex) else {
            completion(.failure(Errors.failedSetupForApplyChangesToSingleFile("Resolver")))
            return
        }
        
        guard let (owningCreds, cloudStorage) = try? fileIndex.getCloudStorage(userRepo: userRepo, services: services) else {
            completion(.failure(Errors.failedSetupForApplyChangesToSingleFile("getCloudStorage")))
            return
        }
        
        let options = CloudStorageFileNameOptions(cloudFolderName: owningCreds.cloudFolderName, mimeType: fileIndex.mimeType)
        
        guard let deviceUUID = fileIndex.deviceUUID else {
            completion(.failure(Errors.couldNotGetDeviceUUID))
            return
        }
        
        guard let priorFileVersion = fileIndex.fileVersion else {
            completion(.failure(Errors.couldNotGetPriorFileVersion))
            return
        }
        
        resolver.apply(changes: uploadsForFileUUID, toFileUUID: fileUUID, currentFileVersion: priorFileVersion, deviceUUID: deviceUUID, cloudStorage: cloudStorage, options: options) { [weak self] result in
            guard let self = self else { return }
            
            switch result {
            case .failure(let error):
                completion(.failure(error))
                
            case .success(let applyResult):
                let updateSuccess = self.fileIndexRepo.update(indexId: fileIndex.fileIndexId, with: [
                    FileIndex.lastUploadedCheckSumKey: .string(applyResult.checkSum),
                    FileIndex.fileVersionKey: .int32(applyResult.newFileVersion),
                    FileIndex.updateDateKey: .dateTime(Date())
                 ])
                
                guard updateSuccess else {
                    completion(.failure(Errors.failedUpdatingFileIndex))
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
                        completion(.failure(Errors.failedRemovingUploadRow))
                        return
                    }
                }
                
                // Don't do deletions yet. The overall operations can't be repeated if the original files are gone.
                let currentCloudFileName = Filename.inCloud(deviceUUID: deviceUUID, fileUUID: fileUUID, mimeType: options.mimeType, fileVersion: priorFileVersion)
                let deletion = FileDeletion(cloudStorage: cloudStorage, cloudFileName: currentCloudFileName, options: options)
                self.fileDeletions += [deletion]
                
                completion(.success(uploadsForFileUUID))
            }
        }
    }
}
