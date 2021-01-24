//
//  FileController+UploadDeletion.swift
//  Server
//
//  Created by Christopher Prince on 3/22/17.
//
//

import Foundation
import LoggerAPI
import ServerShared
import Kitura

/* Algorithm:

1) Gets the database key for
    a) the fileUUID if the request one
    b) the fileGroupUUID, if the deletion request has one
2) Gets all the [FileInfo] objects for the files for those keys
3) If all of the files are already marked as deleted, returns success.
    Just a repeated attempt to delete the same file.
4) If at least one file not yet deleted, marks the FileIndex as deleted for all of the files.
    Doesn't yet delete the file in Cloud Storage.
5) Creates a DeferredUpload, and
    a) If this deletion is for one fileUUID, creates a Upload record.
        and links in the DeferredUpload
    b) If this deletion is for a fileGroupUUID, doesn't create an Upload record.
6) The Uploader will then (asynchonously):
    a) For a single fileUUID
        Flush out any DeferredUpload record(s) for that file
        And remove any Upload record(s).
        Delete the file from Cloud Storage.
    b) For a fileGroupUUID
        Flush out any DeferredUpload record(s) for the files associated with that file group.
        And remove any Upload record(s) for that file group.
        Delete the file(s) from Cloud Storage.
 */

extension FileController {
    func uploadDeletion(params:RequestProcessingParameters) {
        guard let uploadDeletionRequest = params.request as? UploadDeletionRequest else {
            let message = "Did not receive UploadDeletionRequest"
            Log.error(message)
            params.completion(.failure(.message(message)))
            return
        }
        
        guard let deviceUUID = params.deviceUUID else {
            let message = "No deviceUUID in UploadDeletionRequest"
            Log.error(message)
            params.completion(.failure(.message(message)))
            return
        }
        
        guard let sharingGroupUUID = uploadDeletionRequest.sharingGroupUUID,
            sharingGroupSecurityCheck(sharingGroupUUID: sharingGroupUUID, params: params) else {
            let message = "Failed in sharing group security check."
            Log.error(message)
            params.completion(.failure(.message(message)))
            return
        }
        
        // Do we have a fileUUID or a fileGroupUUID?
        
        var keys = [FileIndexRepository.LookupKey]()
        
        enum DeletionType {
            case singleFile
            case fileGroup
        }
        let deletionType: DeletionType
        
        if let fileUUID = uploadDeletionRequest.fileUUID {
            let key = FileIndexRepository.LookupKey.primaryKeys(sharingGroupUUID: uploadDeletionRequest.sharingGroupUUID, fileUUID: fileUUID)
            keys += [key]
            deletionType = .singleFile
        }
        else if let fileGroupUUID = uploadDeletionRequest.fileGroupUUID {
            let key = FileIndexRepository.LookupKey.fileGroupUUIDAndSharingGroup(fileGroupUUID: fileGroupUUID, sharingGroupUUID: uploadDeletionRequest.sharingGroupUUID)
            keys += [key]
            deletionType = .fileGroup
        }
        else {
            let message = "Did not have either a fileUUID or a fileGroupUUID"
            Log.error(message)
            params.completion(.failure(.message(message)))
            return
        }
        
        let files:[FileInfo]
        
        let indexResult = params.repos.fileIndex.fileIndex(forKeys: keys)
        switch indexResult {
        case .error(let error):
            Log.error(error)
            params.completion(.failure(.message(error)))
            return
        case .fileIndex(let fileInfos):
            files = fileInfos
        }
        
        guard files.count > 0 else {
            let message = "File(s) \(keys) not in FileIndex"
            Log.error(message)
            params.completion(.failure(.message(message)))
            return
        }
        
        // Are all of the file(s) marked as deleted?
        if (files.filter {$0.deleted == true}).count == files.count {
            Log.info("File(s) already marked as deleted: Not deleting again.")
            let response = UploadDeletionResponse()
            params.completion(.success(response))
            return
        }
        
        // Mark the file(s) as deleted in the FileIndex
        for key in keys {
            guard let _ = params.repos.fileIndex.markFilesAsDeleted(key: key) else {
                let message = "Failed marking file(s) as deleted: \(key)"
                Log.error(message)
                params.completion(.failure(.message(message)))
                return
            }
        }
        
        let finishType:FinishUploadDeletion.DeletionsType
        
        switch deletionType {
        case .fileGroup:
            finishType = .fileGroup(fileGroupUUID: uploadDeletionRequest.fileGroupUUID)
            
        case .singleFile:
            guard files.count == 1 else {
                let message = "Single file deletion and not exactly one file."
                Log.error(message)
                params.completion(.failure(.message(message)))
                return
            }
            
            let file = files[0]
            
            guard file.fileGroupUUID == nil else {
                let message = "Single file deletion but the file had a file group."
                Log.error(message)
                params.completion(.failure(.message(message)))
                return
            }
            
            guard let fileUUID = file.fileUUID else {
                let message = "Single file deletion and no fileUUID given."
                Log.error(message)
                params.completion(.failure(.message(message)))
                return
            }
            
            Log.info("Upload deletion for fileUUID: ")
                        
            let upload = Upload()
            upload.fileUUID = fileUUID
            upload.deviceUUID = deviceUUID
            upload.state = .deleteSingleFile
            upload.userId = params.currentSignedInUser!.userId
            upload.sharingGroupUUID = sharingGroupUUID
            
            // So we don't get failures due to nil checks.
            upload.uploadCount = 1
            upload.uploadIndex = 1
            
            let uploadAddResult = params.repos.upload.add(upload: upload)
            
            switch uploadAddResult {
            case .success(_):
                finishType = .singleFile(upload: upload)

            default:
                let message = "Error adding Upload record: \(uploadAddResult)"
                Log.error(message)
                params.completion(.failure(.message(message)))
                return
            }
        }
        
        let uploader = Uploader(services: params.services.uploaderServices, delegate: params.services)

        do {
            let finishUploads = try FinishUploadDeletion(type: finishType, uploader: uploader, sharingGroupUUID: sharingGroupUUID, params: params)
            let result = try finishUploads.finish()
            
            switch result {
            case .deferred(let deferredUploadId, let runner):
                Log.info("Success deleting files: Subject to deferred transfer.")
                let response = UploadDeletionResponse()
                response.deferredUploadId = deferredUploadId
                params.completion(.successWithRunner(response, runner: runner))
                
            case .error:
                let message = "Could not complete FinishUploads"
                Log.error(message)
                params.completion(.failure(.message(message)))
            }
        } catch let error {
            let message = "Could not finish FinishUploads: \(error)"
            Log.error(message)
            params.completion(.failure(.message(message)))
            return
        }
    }
}
