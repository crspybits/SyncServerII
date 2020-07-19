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
    1) Need to get the Account for the owner for this fileGroupUUID.
    2) let allUploads = all of the Upload records corresponding to these DeferredUpload's.
    3) let fileUUIDs = the set of unique fileUUID's within allUploads.
    4) let uploads(fileUUID) be the set of Upload's for a given fileUUID within fileUUIDs, i.e., within allUploads.
    5) for fileUUID in fileUUIDs {
         let uploadsForFileUUID = uploads(fileUUID)
         Get the change resolver for this fileUUID from the FileIndex
         Read the file indicated by fileUUID from cloud storage.
         for upload in uploadsForFileUUID {
           Apply the change in upload to the file data using the change resolver.
         }
         Write the file data for the updated file back to cloud storage.
       }
    6) Do the update of the FileIndex based on these DeferredUpload records.
    7) Remove these DeferredUpload from the database.
    8) End the database transaction.
 */

// Process a group of deferred uploads, for a single fileGroupUUID.
// All DeferredUploads given must have the fileGroupUUID given.
// Call the `run` method to kick this off. Once this succeeds, caller should remove the DeferredUpload records. Caller needs to take care of surrounding this with a database transaction. The concept is that, for consistency purposes, all changes for a single file group, need to be applied, or none need to be applied.
// NOTE: Currently this statement of consistency applies at the database level, but not at the file level. If this fails mid-way through processing, new file versions may be present. We need to put in some code to deal with a restart which itself doesn't fail if the a new file version is present. Perhaps overwrite it?
class ApplyDeferredUploads {
    let sharingGroupUUID: String
    let fileGroupUUID: String
    let deferredUploads: [DeferredUpload]
    let db: Database
    let allUploads: [Upload]
    let fileIndexRepo: FileIndexRepository
    let accountManager: AccountManager
    let resolverManager: ChangeResolverManager
    let fileUUIDs: [String]
    let uploadRepo:UploadRepository
    let deferredUploadRepo:DeferredUploadRepository
    var fileDeletions = [FileDeletion]()
    
    init?(sharingGroupUUID: String, fileGroupUUID: String, deferredUploads: [DeferredUpload], accountManager: AccountManager, resolverManager: ChangeResolverManager, db: Database) throws {
        self.sharingGroupUUID = sharingGroupUUID
        self.fileGroupUUID = fileGroupUUID
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
        
        guard (deferredUploads.filter {$0.fileGroupUUID == fileGroupUUID}).count == deferredUploads.count else {
            throw UploaderError.notAllInGroupHaveSameFileGroupUUID
        }
        
        let deferredUploadIds = deferredUploads.compactMap{$0.deferredUploadId}
        guard deferredUploads.count == deferredUploadIds.count else {
            throw UploaderError.deferredUploadIds
        }
        
        guard let allUploads = UploadRepository(db).select(forDeferredUploadIds: deferredUploadIds) else {
            throw UploaderError.couldNotGetAllUploads
        }
        self.allUploads = allUploads
        
        let fileUUIDs = allUploads.compactMap{$0.fileUUID}
        guard fileUUIDs.count == allUploads.count else {
            throw UploaderError.couldNotGetFileUUIDs
        }
        
        // Now that we have the fileUUIDs, we need to make sure they are unique.
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
                completion(UploaderError.failedRemovingDeferredUpload)
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
            throw UploaderError.couldNotLookupFileUUID
        }
        
        return fileIndex
    }
    
    func getCloudStorage(forFileUUID fileUUID: String, usingFileIndex fileIndex: FileIndex) throws -> (Account, CloudStorage) {
        guard let owningUserCreds = FileController.getCreds(forUserId: fileIndex.userId, from: db, accountManager: accountManager) else {
            throw UploaderError.couldNotGetOwningUserCreds
        }
        
        guard let cloudStorage = owningUserCreds as? CloudStorage else {
            throw UploaderError.couldNotConvertToCloudStorage
        }
        
        return (owningUserCreds, cloudStorage)
    }
    
    func changeResolver(forFileUUID fileUUID: String, usingFileIndex fileIndex: FileIndex) throws -> ChangeResolver.Type {
        guard let changeResolverName = fileIndex.changeResolverName else {
            Log.error("couldNotLookupResolverName")
            throw UploaderError.couldNotLookupResolverName
        }
        
        guard let resolverType = resolverManager.getResolverType(changeResolverName) else {
            Log.error("couldNotLookupResolver")
            throw UploaderError.couldNotLookupResolver
        }
        
        return resolverType
    }
    
    // Apply changes to all fileUUIDs. Kick off with default `withFileIndex`.
    // This deals with database transactions.
    func run(completion: @escaping (Error?)->()) {
        guard db.startTransaction() else {
            completion(UploaderError.failedStartingTransaction)
            return
        }
        
        run(withFileIndex: 0) { error in
            guard error == nil else {
                _ = self.db.rollback()
                completion(error)
                return
            }
            
            guard self.db.commit() else {
                completion(UploaderError.couldNotCommit)
                return
            }
            
            Log.info("About to start cleanup.")
            self.cleanup(completion: completion)
        }
    }
    
    private func run(withFileIndex fileIndex: Int, completion: @escaping (Error?)->()) {
        // Base case of recursion
        guard fileIndex < fileUUIDs.count else {
            completion(nil)
            return
        }
        
        let currentFileUUID = fileUUIDs[fileIndex]
        
        Log.debug("applyChangesToSingleFile: \(currentFileUUID)")

        applyChangesToSingleFile(fileUUID: currentFileUUID) {[unowned self] error in
            guard error == nil else {
                completion(error)
                return
            }
            
            DispatchQueue.global(qos: .default).async {
                self.run(withFileIndex: fileIndex + 1) { error in
                    guard error == nil else {
                        completion(error)
                        return
                    }
                    
                    completion(nil)
                }
            }
        }
    }
    
    func applyChangesToSingleFile(fileUUID: String, completion: @escaping (Error?)->()) {
        let uploadsForFileUUID = uploads(fileUUID: fileUUID)
        
        guard let fileIndex = try? getFileIndex(forFileUUID: fileUUID) else {
            completion(UploaderError.failedSetupForApplyChangesToSingleFile("FileIndex"))
            return
        }
        
        guard let resolver = try? changeResolver(forFileUUID: fileUUID, usingFileIndex: fileIndex) else {
            completion(UploaderError.failedSetupForApplyChangesToSingleFile("Resolver"))
            return
        }
        
        guard let (owningCreds, cloudStorage) = try? getCloudStorage(forFileUUID: fileUUID, usingFileIndex: fileIndex) else {
            completion(UploaderError.failedSetupForApplyChangesToSingleFile("getCloudStorage"))
            return
        }
        
        // Only a single type of change resolver protocol so far. Need changes here when we add another.
        guard let wholeFileReplacer = resolver as? WholeFileReplacer.Type else {
            completion(UploaderError.unknownResolverType)
            return
        }
        
        // We're applying changes and creating the next version of the file
        let nextVersion = fileIndex.fileVersion + 1
        
        guard let deviceUUID = fileIndex.deviceUUID else {
            completion(UploaderError.couldNotGetDeviceUUID)
            return
        }
        
        let currentCloudFileName = Filename.inCloud(deviceUUID:deviceUUID, fileUUID: fileUUID, mimeType:fileIndex.mimeType, fileVersion: fileIndex.fileVersion)
        let options = CloudStorageFileNameOptions(cloudFolderName: owningCreds.cloudFolderName, mimeType: fileIndex.mimeType)
        
        cloudStorage.downloadFile(cloudFileName: currentCloudFileName, options: options) { downloadResult in
            guard case .success(data: let fileContents, checkSum: _) = downloadResult else {
                completion(UploaderError.downloadError(downloadResult))
                return
            }
            
            guard var replacer = try? wholeFileReplacer.init(with: fileContents) else {
                completion(UploaderError.failedInitializingWholeFileReplacer)
                return
            }
            
            for upload in uploadsForFileUUID {
                guard let changeData = upload.uploadContents else {
                    completion(UploaderError.noContentsForUpload)
                    return
                }
                
                do {
                    try replacer.add(newRecord: changeData)
                } catch let error {
                    completion(UploaderError.failedAddingChange(error))
                    return
                }
            }
            
            guard let replacementFileContents = try? replacer.getData() else {
                completion(UploaderError.failedGettingReplacerData)
                return
            }
            
            let nextCloudFileName = Filename.inCloud(deviceUUID:deviceUUID, fileUUID: fileUUID, mimeType:fileIndex.mimeType, fileVersion: nextVersion)
            
            cloudStorage.uploadFile(cloudFileName: nextCloudFileName, data: replacementFileContents, options: options) {[unowned self] uploadResult in
                guard case .success(let checkSum) = uploadResult else {
                    completion(UploaderError.failedUploadingNewFileVersion)
                    return
                }
                
                fileIndex.lastUploadedCheckSum = checkSum
                fileIndex.fileVersion = nextVersion
                fileIndex.updateDate = Date()
                
                guard self.fileIndexRepo.update(fileIndex: fileIndex) else {
                    completion(UploaderError.failedUpdatingFileIndex)
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
                        completion(UploaderError.failedRemovingUploadRow)
                        return
                    }
                }
                
                // Don't do deletions yet. The overall operations can't be repeated if the original files are gone.
                let deletion = FileDeletion(cloudStorage: cloudStorage, cloudFileName: currentCloudFileName, options: options)
                self.fileDeletions += [deletion]
                
                completion(nil)
            }
        }
    }
}
