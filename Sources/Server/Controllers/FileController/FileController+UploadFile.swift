//
//  FileController+UploadFile.swift
//  Server
//
//  Created by Christopher Prince on 3/22/17.
//
//

import Foundation
import LoggerAPI
import SyncServerShared
import Kitura

extension FileController {
    private struct Cleanup {
        let cloudFileName: String
        let options: CloudStorageFileNameOptions
        let ownerCloudStorage: CloudStorage
    }
    
    private enum Info {
        case success(response:UploadFileResponse)
        case errorMessage(String)
        case errorResponse(RequestProcessingParameters.Response)
        case errorCleanup(message: String, cleanup: Cleanup)
    }

    private func finish(_ info: Info, params:RequestProcessingParameters) {
        // This is just a convenience so I don't have to pass the sharingGroupUUID on each call to `finish`-- It won't fail since we already did this befe.
        guard let uploadRequest = params.request as? UploadFileRequest,
            let sharingGroupUUID = uploadRequest.sharingGroupUUID else {
            let message = "Should never get here: We already did this before."
            Log.error(message)
            params.completion(.failure(.message(message)))
            return
        }
    
        Lock.unlock(db: params.db, sharingGroupUUID: sharingGroupUUID)
        
        switch info {
        case .errorResponse(let response):
            params.completion(response)
            
        case .errorMessage(let message):
            Log.error(message)
            params.completion(.failure(.message(message)))
            
        case .errorCleanup(message: let message, cleanup: let cleanup):
            cleanup.ownerCloudStorage.deleteFile(cloudFileName: cleanup.cloudFileName, options: cleanup.options, completion: {_ in
                Log.error(message)
                params.completion(.failure(.message(message)))
            })
            
        case .success(response: let response):
            params.completion(.success(response))
        }
    }
    
    func uploadFile(params:RequestProcessingParameters) {
        guard let uploadRequest = params.request as? UploadFileRequest else {
            let message = "Did not receive UploadFileRequest"
            Log.error(message)
            params.completion(.failure(.message(message)))
            return
        }
        
        // 6/23/19; Putting a lock here because of a deadlock issue. See [1].
        
        guard Lock.lock(db: params.db, sharingGroupUUID: uploadRequest.sharingGroupUUID) else {
            finish(.errorMessage("Failed to get lock for: \(String(describing: uploadRequest.sharingGroupUUID))"), params: params)
            return
        }
        
        guard sharingGroupSecurityCheck(sharingGroupUUID: uploadRequest.sharingGroupUUID, params: params) else {
            finish(.errorMessage("Failed in sharing group security check."), params: params)
            return
        }
        
        guard let _ = MimeType(rawValue: uploadRequest.mimeType) else {
            let message = "Unknown mime type passed: \(String(describing: uploadRequest.mimeType)) (see SyncServer-Shared)"
            finish(.errorMessage(message), params: params)
            return
        }
        
        guard uploadRequest.fileVersion != nil else {
            let message = "File version not given in upload request."
            finish(.errorMessage(message), params: params)
            return
        }
        
        Log.debug("uploadRequest.sharingGroupUUID: \(String(describing: uploadRequest.sharingGroupUUID))")
        
        Controllers.getMasterVersion(sharingGroupUUID: uploadRequest.sharingGroupUUID, params: params) { error, masterVersion in
            if error != nil {
                let message = "Error: \(String(describing: error))"
                finish(.errorMessage(message), params: params)
                return
            }

            if masterVersion != uploadRequest.masterVersion {
                let response = UploadFileResponse()
                Log.warning("Master version update: \(String(describing: masterVersion))")
                response.masterVersionUpdate = masterVersion
                finish(.success(response: response), params: params)
                return
            }
            
            // Check to see if (a) this file is already present in the FileIndex, and if so then (b) is the version being uploaded +1 from that in the FileIndex.
            var existingFileInFileIndex:FileIndex?
            do {
                existingFileInFileIndex = try FileController.checkForExistingFile(params:params, sharingGroupUUID: uploadRequest.sharingGroupUUID, fileUUID:uploadRequest.fileUUID)
            } catch (let error) {
                let message = "Could not lookup file in FileIndex: \(error)"
                finish(.errorMessage(message), params: params)
                return
            }
        
            guard UploadRepository.isValidAppMetaDataUpload(
                currServerAppMetaDataVersion: existingFileInFileIndex?.appMetaDataVersion,
                currServerAppMetaData:
                    existingFileInFileIndex?.appMetaData,
                optionalUpload:uploadRequest.appMetaData) else {
                let message = "App meta data or version is not valid for upload."
                finish(.errorMessage(message), params: params)
                return
            }
            
            // To send back to client.
            var creationDate:Date!
            
            let todaysDate = Date()
            
            var newFile = true
            if let existingFileInFileIndex = existingFileInFileIndex {
                if existingFileInFileIndex.deleted && (uploadRequest.undeleteServerFile == nil || uploadRequest.undeleteServerFile == false) {
                    let message = "Attempt to upload an existing file, but it has already been deleted."
                    finish(.errorMessage(message), params: params)
                    return
                }
            
                newFile = false
                guard existingFileInFileIndex.fileVersion + 1 == uploadRequest.fileVersion else {
                    let message = "File version being uploaded (\(String(describing: uploadRequest.fileVersion))) is not +1 of current version: \(String(describing: existingFileInFileIndex.fileVersion))"
                    finish(.errorMessage(message), params: params)
                    return
                }
                
                guard existingFileInFileIndex.mimeType == uploadRequest.mimeType else {
                    let message = "File being uploaded(\(String(describing: uploadRequest.mimeType))) doesn't have the same mime type as current version: \(String(describing: existingFileInFileIndex.mimeType))"
                    finish(.errorMessage(message), params: params)
                    return
                }
                
                creationDate = existingFileInFileIndex.creationDate
            }
            else {
                if uploadRequest.undeleteServerFile != nil && uploadRequest.undeleteServerFile == true  {
                    let message = "Attempt to undelete a file but it's a new file!"
                    finish(.errorMessage(message), params: params)
                    return
                }
                
                // File isn't yet in the FileIndex-- must be a new file. Thus, must be version 0.
                guard uploadRequest.fileVersion == 0 else {
                    let message = "File is new, but file version being uploaded (\(String(describing: uploadRequest.fileVersion))) is not 0"
                    finish(.errorMessage(message), params: params)
                    return
                }
            
                // 8/9/17; I'm no longer going to use a date from the client for dates/times-- clients can lie.
                // https://github.com/crspybits/SyncServerII/issues/4
                creationDate = todaysDate
            }
            
            var ownerCloudStorage:CloudStorage!
            var ownerAccount:Account!
            
            if newFile {
                // OWNER
                // establish the v0 owner of the file.
                ownerAccount = params.effectiveOwningUserCreds
            }
            else {
                // OWNER
                // Need to get creds for the user that uploaded the v0 file.
                ownerAccount = FileController.getCreds(forUserId: existingFileInFileIndex!.userId, from: params.db, delegate: params.accountDelegate)
            }
            
            ownerCloudStorage = ownerAccount as? CloudStorage
            guard ownerCloudStorage != nil && ownerAccount != nil else {
                let message = "Could not obtain creds for v0 file: Assuming this means owning user is no longer on system."
                Log.error(message)
                finish(.errorResponse(.failure(
                    .goneWithReason(message: message, .userRemoved))), params: params)
                return
            }
            
            // There is an unlikely race condition here -- two processes (within the same app, with the same deviceUUID) could be uploading the same file at the same time, both could upload, but only one would be able to create the Upload entry. I'm going to assume that this will not happen: That a single app/cilent will only upload the same file once at one time. (I used to create the Upload table entry first to avoid this race condition, but it's unlikely and leads to some locking issues-- see [1]).
            
            // Check to see if the file is present already-- i.e., if has been uploaded already.
            let key = UploadRepository.LookupKey.primaryKey(fileUUID: uploadRequest.fileUUID, userId: params.currentSignedInUser!.userId, deviceUUID: params.deviceUUID!)
            let lookupResult = params.repos.upload.lookup(key: key, modelInit: Upload.init)
        
            switch lookupResult {
            case .found(let model):
                Log.info("File was already present: Not uploading again.")
                let upload = model as! Upload
                let response = UploadFileResponse()

                // 12/27/17; Send the dates back down to the client. https://github.com/crspybits/SharedImages/issues/44
                response.creationDate = creationDate
                response.updateDate = upload.updateDate
                finish(.success(response: response), params: params)
                return
                
            case .noObjectFound:
                // Expected result
                break
                
            case .error(let message):
                finish(.errorMessage(message), params: params)
                return
            }
            
            let cloudFileName = uploadRequest.cloudFileName(deviceUUID:params.deviceUUID!, mimeType: uploadRequest.mimeType)
            
            guard let mimeType = uploadRequest.mimeType else {
                let message = "No mimeType given!"
                finish(.errorMessage(message), params: params)
                return
            }
            
            // Releasing the lock because we don't want to hold it for the arbitrarily long duration of the upload. This will mean someone else could sneek in and upload the next version of the same file while we don't have the lock. Not sure what to do about that tho.
            guard Lock.unlock(db: params.db, sharingGroupUUID: uploadRequest.sharingGroupUUID) else {
                let message = "Could not release lock!"
                finish(.errorMessage(message), params: params)
                return
            }
            
            Log.info("File being sent to cloud storage: \(cloudFileName)")

            let options = CloudStorageFileNameOptions(cloudFolderName: ownerAccount.cloudFolderName, mimeType: mimeType)
            
            let cleanup = Cleanup(cloudFileName: cloudFileName, options: options, ownerCloudStorage: ownerCloudStorage)
            
            ownerCloudStorage.uploadFile(cloudFileName:cloudFileName, data: uploadRequest.data, options:options) {[unowned self] result in
                switch result {
                case .success(let checkSum):
                    Log.debug("File with checkSum \(checkSum) successfully uploaded!")
                    
                    // Reacquire the lock
                    guard Lock.lock(db: params.db, sharingGroupUUID: uploadRequest.sharingGroupUUID) else {
                        self.finish(.errorCleanup(message: "Failed to get lock after upload", cleanup: cleanup), params: params)
                        return
                    }
                    
                    self.addUploadEntry(newFile: newFile, creationDate: creationDate, todaysDate: todaysDate, uploadedCheckSum: checkSum, cleanup: cleanup, params: params, uploadRequest: uploadRequest)
                    
                case .accessTokenRevokedOrExpired:
                    // Not going to do any cleanup. The access token has expired/been revoked. Presumably, the file wasn't uploaded.
                    let message = "Access token revoked or expired."
                    Log.error(message)
                    self.finish(.errorResponse(.failure(
                        .goneWithReason(message: message, .authTokenExpiredOrRevoked))), params: params)
                    
                case .failure(let error):
                    let message = "Could not uploadFile: error: \(error)"
                    self.finish(.errorCleanup(message: message, cleanup: cleanup), params: params)
                }
            }
        }
    }
    
    private func addUploadEntry(newFile: Bool, creationDate: Date, todaysDate: Date, uploadedCheckSum: String, cleanup: Cleanup, params:RequestProcessingParameters, uploadRequest: UploadFileRequest) {
        let upload = Upload()
        upload.deviceUUID = params.deviceUUID
        upload.fileUUID = uploadRequest.fileUUID
        upload.fileVersion = uploadRequest.fileVersion
        upload.mimeType = uploadRequest.mimeType
        upload.sharingGroupUUID = uploadRequest.sharingGroupUUID
        
        // Waiting until now to check UploadRequest checksum because what's finally important is that the checksum before the upload is the same as that computed by the cloud storage service.
        let expectedCheckSum = uploadRequest.checkSum?.lowercased()
        guard uploadedCheckSum == expectedCheckSum else {
            let message = "Checksum after upload to cloud storage (\(uploadedCheckSum) is not the same as before upload \(String(describing: expectedCheckSum))."
            finish(.errorCleanup(message: message, cleanup: cleanup), params: params)
            return
        }

        upload.lastUploadedCheckSum = uploadedCheckSum
    
        if let fileGroupUUID = uploadRequest.fileGroupUUID {
            guard uploadRequest.fileVersion == 0 else {
                let message = "fileGroupUUID was given, but file version being uploaded (\(String(describing: uploadRequest.fileVersion))) is not 0"
                finish(.errorCleanup(message: message, cleanup: cleanup), params: params)
                return
            }
            
            upload.fileGroupUUID = fileGroupUUID
        }
    
        if uploadRequest.undeleteServerFile != nil && uploadRequest.undeleteServerFile == true {
            Log.info("Undeleted server file.")
            upload.state = .uploadedUndelete
        }
        else {
            upload.state = .uploadedFile
        }
    
        // We are using the current signed in user's id here (and not the effective user id) because we need a way of indexing or organizing the collection of files uploaded by a particular user.
        upload.userId = params.currentSignedInUser!.userId
    
        upload.appMetaData = uploadRequest.appMetaData?.contents
        upload.appMetaDataVersion = uploadRequest.appMetaData?.version

        if newFile {
            upload.creationDate = creationDate
        }
    
        upload.updateDate = todaysDate
    
        let addUploadResult = params.repos.upload.retry {
            return params.repos.upload.add(upload: upload, fileInFileIndex: !newFile)
        }
        
        switch addUploadResult {
        case .success:
            let response = UploadFileResponse()

            // 12/27/17; Send the dates back down to the client. https://github.com/crspybits/SharedImages/issues/44
            response.creationDate = creationDate
            response.updateDate = upload.updateDate
            finish(.success(response: response), params: params)
            
        case .duplicateEntry:
            finish(.errorCleanup(message: "Violated assumption: Two uploads by same app at the same time?", cleanup: cleanup), params: params)
            
        case .aModelValueWasNil:
            finish(.errorCleanup(message: "A model value was nil!", cleanup: cleanup), params: params)
            
        case .deadlock:
            finish(.errorCleanup(message: "Deadlock", cleanup: cleanup), params: params)
            
        case .waitTimeout:
            finish(.errorCleanup(message: "WaitTimeout", cleanup: cleanup), params: params)

        case .otherError(let error):
            finish(.errorCleanup(message: error, cleanup: cleanup), params: params)
        }
    }
}

/* [1]
I'm getting another deadlock situation. It's happening on a DoneUploads, and a deletion from the Upload table. I'm thinking it has to do with an interaction with an Upload.

What happens if:

a) An upload occurs for sharing group X.
b) While the upload is uploading, a DoneUploads for sharing group X occurs.

sharingGroupUUID's are a foreign key. I'm assuming that inserting into Upload for sharing group X causes some kind of lock based on that sharing group X value. When the DoneUploads tries to delete from Upload, for that same sharing group, it gets a conflict.

Conclusion: To deal with this, I'm (1) not adding the record to the Upload table until *after* the upload, and (2) only doing that when I am holding the sharing group lock.
*/
