//
//  Uploader+UploadDeletion.swift
//  Server
//
//  Created by Christopher G Prince on 8/2/20.
//

import Foundation
import ServerAccount
import ServerShared
import LoggerAPI

extension Uploader {
    private func getDeletionFrom(fileIndex: FileIndex) throws -> FileDeletion {
        guard let (owningCreds, cloudStorage) = try? fileIndex.getCloudStorage(userRepo: userRepo, accountManager: accountManager) else {
            throw Errors.failedGettingCloudStorage
        }
        
        let options = CloudStorageFileNameOptions(cloudFolderName: owningCreds.cloudFolderName, mimeType: fileIndex.mimeType)
        let cloudFileName = Filename.inCloud(deviceUUID: fileIndex.deviceUUID, fileUUID: fileIndex.fileUUID, mimeType: fileIndex.mimeType, fileVersion: fileIndex.fileVersion)
        return FileDeletion(cloudStorage: cloudStorage, cloudFileName: cloudFileName, options: options)
    }
    
    // Do the actual file deletions
    func processFileDeletions(deferredUploads: [DeferredUpload]) throws {
        guard db.startTransaction() else {
            throw Errors.failedStartingDatabaseTransaction
        }
        
        do {
            try processFileDeletionsWithoutTransaction(deferredUploads: deferredUploads)
        } catch let error {
            _ = db.rollback()
            throw error
        }
        
        guard db.commit() else {
            _ = db.rollback()
            throw Errors.failedCommittingDatabaseTransaction
        }
    }

    private func processFileDeletionsWithoutTransaction(deferredUploads: [DeferredUpload]) throws {
        guard deferredUploads.count > 0 else {
            return
        }
        
        var deletions = [FileDeletion]()
        
        // Case 1) Upload deletions when we're removing entire file groups. (Have no Upload records for these).
        let deferredUploadsWithFileGroups = deferredUploads.filter {$0.fileGroupUUID != nil}
        for deferredUploadWithFileGroup in deferredUploadsWithFileGroups {
            let key = FileIndexRepository.LookupKey.fileGroupUUIDAndSharingGroup(fileGroupUUID: deferredUploadWithFileGroup.fileGroupUUID!, sharingGroupUUID: deferredUploadWithFileGroup.sharingGroupUUID)
            guard let fileIndexes = fileIndexRepo.lookupAll(key: key, modelInit: FileIndex.init) else {
                throw Errors.couldNotLookupByGroups
            }
            
            for fileIndex in fileIndexes {
                deletions += [try getDeletionFrom(fileIndex: fileIndex)]
            }
        }
             
        // Case 2) Upload deletions when we're removing files with no file groups.
        let deferredDeletionsWithoutFileGroups = deferredUploads.filter {$0.fileGroupUUID == nil}
        let deferredUploadIds = deferredDeletionsWithoutFileGroups.compactMap {$0.deferredUploadId}
        guard deferredDeletionsWithoutFileGroups.count == deferredUploadIds.count else {
            throw Errors.mismatchWithDeferredUploadIdsCount
        }
        
        var uploads = [Upload]()
        
        if deferredUploadIds.count > 0 {
            guard let theUploads = uploadRepo.select(forDeferredUploadIds: deferredUploadIds) else {
                throw Errors.failedToGetUploads
            }
            
            uploads = theUploads
            
            for upload in uploads {
                guard let sharingGroupUUID = upload.sharingGroupUUID else {
                    throw Errors.failedToGetSharingGroupUUID
                }
                
                guard let fileUUID = upload.fileUUID else {
                    throw Errors.failedToGetFileUUID
                }
                
                let key = FileIndexRepository.LookupKey.primaryKeys(sharingGroupUUID: sharingGroupUUID, fileUUID: fileUUID)
                guard case .found(let model) = fileIndexRepo.lookup(key: key, modelInit: FileIndex.init), let fileIndex = model as? FileIndex else {
                    throw Errors.failedToGetFileUUID
                }
                
                deletions += [try getDeletionFrom(fileIndex: fileIndex)]
            }
        }
        
        // Not going to worry about any resulting errors because: (a) we might be trying the deletion a 2nd time and the file might just not be there, (b) the consequences of leaving a file in cloud storage are not dire-- just some "garbage" that could possibly be cleaned up later.
        if let errors = FileDeletion.apply(deletions: deletions) {
            Log.warning("Some error(s) occurred while deleting files: \(errors)")
        }
        
        // Now, delete the database records.
        
        for upload in uploads {
            let key = UploadRepository.LookupKey.uploadId(upload.uploadId)
            guard case .removed = uploadRepo.remove(key: key) else {
                throw Errors.couldNotRemoveUploadRow
            }
        }
        
        for deferredUpload in deferredUploads {
            let key = DeferredUploadRepository.LookupKey.deferredUploadId(deferredUpload.deferredUploadId)
            guard case .removed = deferredUploadRepo.remove(key: key) else {
                throw Errors.couldNotRemoveUploadRow
            }
        }
    }
}
