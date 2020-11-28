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
        guard let (owningCreds, cloudStorage) = try? fileIndex.getCloudStorage(userRepo: userRepo, services: services) else {
            throw Errors.failedGettingCloudStorage
        }
        
        let options = CloudStorageFileNameOptions(cloudFolderName: owningCreds.cloudFolderName, mimeType: fileIndex.mimeType)
        let cloudFileName = Filename.inCloud(deviceUUID: fileIndex.deviceUUID, fileUUID: fileIndex.fileUUID, mimeType: fileIndex.mimeType, fileVersion: fileIndex.fileVersion)
        return FileDeletion(cloudStorage: cloudStorage, cloudFileName: cloudFileName, options: options)
    }
    
    // Do the actual file deletions
    func processFileDeletions(deferredUploads: [DeferredUpload]) throws {
        guard try getDbConnection().startTransaction() else {
            throw Errors.failedStartingDatabaseTransaction
        }
        
        do {
            try processFileDeletionsWithoutTransaction(deferredUploads: deferredUploads)
        } catch let error {
            _ = try getDbConnection().rollback()
            throw error
        }
        
        guard try getDbConnection().commit() else {
            _ = try getDbConnection().rollback()
            throw Errors.failedCommittingDatabaseTransaction
        }
    }

    private func processFileDeletionsWithoutTransaction(deferredUploads: [DeferredUpload]) throws {
        guard deferredUploads.count > 0 else {
            return
        }
        
        var fileDeletions = [FileDeletion]()
        var uploads = [Upload]()
        
        // Case 1) Upload deletions when we're removing entire file groups. Have no Upload records for the deletion, but there are Upload records for changes with the same file group.
        let deferredUploadsWithFileGroups = deferredUploads.filter {$0.fileGroupUUID != nil}
        for deferredUploadWithFileGroup in deferredUploadsWithFileGroups {
            guard let fileGroupUUID = deferredUploadWithFileGroup.fileGroupUUID else {
                throw Errors.couldNotGetFileGroup
            }
            
            let key1 = FileIndexRepository.LookupKey.fileGroupUUIDAndSharingGroup(fileGroupUUID: deferredUploadWithFileGroup.fileGroupUUID!, sharingGroupUUID: deferredUploadWithFileGroup.sharingGroupUUID)
            guard let fileIndexes = fileIndexRepo.lookupAll(key: key1, modelInit: FileIndex.init) else {
                throw Errors.couldNotLookupByGroups
            }
            
            let key2 = UploadRepository.LookupKey.fileGroupUUIDWithState(fileGroupUUID: fileGroupUUID, state: .vNUploadFileChange)
            guard let theUploads = uploadRepo.lookupAll(key: key2, modelInit: Upload.init) else {
                throw Errors.failedToGetUploads
            }
            
            uploads += theUploads
            
            for fileIndex in fileIndexes {
                fileDeletions += [try getDeletionFrom(fileIndex: fileIndex)]
            }
        }
             
        // Case 2) Upload deletions when we're removing files with no file groups.
        let deferredDeletionsWithoutFileGroups = deferredUploads.filter {$0.fileGroupUUID == nil}
        let deferredUploadIds = deferredDeletionsWithoutFileGroups.compactMap {$0.deferredUploadId}
        guard deferredDeletionsWithoutFileGroups.count == deferredUploadIds.count else {
            throw Errors.mismatchWithDeferredUploadIdsCount
        }
        
        // Case 2) continued
        if deferredUploadIds.count > 0 {
            guard let theUploads = uploadRepo.select(forDeferredUploadIds: deferredUploadIds) else {
                throw Errors.failedToGetUploads
            }
            
            uploads += theUploads
            
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
                
                fileDeletions += [try getDeletionFrom(fileIndex: fileIndex)]
            }
        }
        
        // End: specific code for Case 1) and Case 2); moving on to more general code.
        
        // Not going to worry about any resulting errors because: (a) we might be trying the deletion a 2nd (or more) time and the file might just not be there, (b) the consequences of leaving a file in cloud storage are not dire-- just some garbage that could possibly be cleaned up later.
        if let errors = FileDeletion.apply(deletions: fileDeletions) {
            Log.warning("Some error(s) occurred while deleting files: \(errors)")
        }
        
        // Now, delete the Upload database records, and change the status of the DeferredUpload records to `completed`.
        
        for upload in uploads {
            let key = UploadRepository.LookupKey.uploadId(upload.uploadId)
            guard case .removed = uploadRepo.remove(key: key) else {
                throw Errors.couldNotRemoveUploadRow
            }
        }
        
        // TODO/DeferredUpload: Test the status change.
        for deferredUpload in deferredUploads {
            guard deferredUploadRepo.update(indexId: deferredUpload.deferredUploadId, with: [DeferredUpload.statusKey: .string(DeferredUploadStatus.completed.rawValue)]) else {
                throw Errors.couldNotUpdateDeferredUploads
            }
        }
    }
}
