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

1) If the deletion request has a fileUUID
    Gets the database key for that file
2) If the deletion request has a fileGroupUUID
    Gets the database key for that file group
3) Gets all the [FileInfo] objects for the files for those keys
4) If all of the files are already marked as deleted, returns success.
    Just a repeated attempt to delete the same file.
5) If at least one file not yet deleted, marks the FileIndex as deleted for all of the files.
    Doesn't yet delete the file in Cloud Storage.
6) Creates a DeferredUpload, and
    a) If this deletion is for one fileUUID, creates a Upload record.
        and links in the DeferredUpload
    b) If this deletion is for a fileGroupUUID, doesn't create an Upload record.
        and links in the DeferredUpload
7) The Uploader will then (asynchonously):
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
        var uploadState: UploadState?
        
        enum DeletionType {
            case singleFile
            case fileGroup
        }
        let deletionType: DeletionType
        
        if let fileUUID = uploadDeletionRequest.fileUUID {
            let key = FileIndexRepository.LookupKey.primaryKeys(sharingGroupUUID: uploadDeletionRequest.sharingGroupUUID, fileUUID: fileUUID)
            keys += [key]
            uploadState = .deleteSingleFile
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
        
        // Are all of the file(s) marked as deleted?
        if (files.filter {$0.deleted == true}).count == files.count {
            Log.info("File(s) already marked as deleted: Not deleting again.")
            let response = UploadDeletionResponse()
            params.completion(.success(response))
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
                
        // Create an entry
        for (index, file) in files.enumerated() {
            let upload = Upload()
            upload.fileUUID = file.fileUUID
            upload.deviceUUID = deviceUUID
            upload.state = uploadState
            upload.userId = params.currentSignedInUser!.userId
            upload.sharingGroupUUID = uploadDeletionRequest.sharingGroupUUID
            upload.fileGroupUUID = file.fileGroupUUID
            upload.uploadIndex = Int32(index + 1)
            upload.uploadCount = Int32(files.count)
            
            let uploadAddResult = params.repos.upload.add(upload: upload)
            
            switch uploadAddResult {
            case .success(_):
                break
                
            default:
                let message = "Error adding Upload record: \(uploadAddResult)"
                Log.error(message)
                params.completion(.failure(.message(message)))
                return
            }
        }
        
        // Really ought to just have a second constructor here. We know that the upload (deletion) is finished. Why make the class guess?
        guard let finishUploads = FinishUploads(sharingGroupUUID: uploadDeletionRequest.sharingGroupUUID, deviceUUID: deviceUUID, uploader: params.uploader, sharingGroupName: nil, params: params) else {
                
            return
        }
        
        finishUploads.transfer()
    }
}
