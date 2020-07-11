//
//  FileController+UploadFile.swift
//  Server
//
//  Created by Christopher Prince on 3/22/17.
//
//

import Foundation
import LoggerAPI
import ServerShared
import Kitura
import ServerAccount

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
        case errorCleanup(message: String, cleanup: Cleanup?)
    }

    private func finish(_ info: Info, params:RequestProcessingParameters) {        
        switch info {
        case .errorResponse(let response):
            params.completion(response)
            
        case .errorMessage(let message):
            Log.error(message)
            params.completion(.failure(.message(message)))
            
        case .errorCleanup(message: let message, cleanup: let cleanup):
            if let cleanup = cleanup {
                cleanup.ownerCloudStorage.deleteFile(cloudFileName: cleanup.cloudFileName, options: cleanup.options, completion: {_ in
                    Log.error(message)
                    params.completion(.failure(.message(message)))
                })
            }
            else {
                Log.error(message)
                params.completion(.failure(.message(message)))
            }
            
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
        
        guard uploadRequest.uploadCount >= 1, uploadRequest.uploadIndex >= 1, uploadRequest.uploadIndex <= uploadRequest.uploadCount else {
            let message = "uploadCount \(String(describing: uploadRequest.uploadCount)) and/or uploadIndex \(String(describing: uploadRequest.uploadIndex)) are invalid."
            Log.error(message)
            params.completion(.failure(.message(message)))
            return
        }
        
        guard let deviceUUID = params.deviceUUID else {
            let message = "Did not have deviceUUID"
            Log.error(message)
            params.completion(.failure(.message(message)))
            return
        }
                
        guard sharingGroupSecurityCheck(sharingGroupUUID: uploadRequest.sharingGroupUUID, params: params) else {
            let message = "Failed in sharing group security check."
            Log.error(message)
            finish(.errorMessage(message), params: params)
            return
        }

        guard let _ = MimeType(rawValue: uploadRequest.mimeType) else {
            let message = "Unknown mime type passed: \(String(describing: uploadRequest.mimeType))"
            finish(.errorMessage(message), params: params)
            return
        }
        
        var existingFileInFileIndex:FileIndex?
        do {
            existingFileInFileIndex = try FileController.checkForExistingFile(params:params, sharingGroupUUID: uploadRequest.sharingGroupUUID, fileUUID:uploadRequest.fileUUID)
        } catch (let error) {
            let message = "Could not lookup file in FileIndex: \(error)"
            finish(.errorMessage(message), params: params)
            return
        }
        
        // To send back to client.
        var creationDate:Date!
        
        let todaysDate = Date()
        
        var newFile = true
        if let existingFileInFileIndex = existingFileInFileIndex {
            guard uploadRequest.appMetaData == nil else {
                let message = "App meta data only allowed with v0 of file."
                finish(.errorMessage(message), params: params)
                return
            }
        
            if existingFileInFileIndex.deleted && (uploadRequest.undeleteServerFile == nil || uploadRequest.undeleteServerFile == false) {
                let message = "Attempt to upload an existing file, but it has already been deleted."
                finish(.errorMessage(message), params: params)
                return
            }
        
            newFile = false
            
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
            
            Log.info("Uploading first version of file.")
        
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
            ownerAccount = FileController.getCreds(forUserId: existingFileInFileIndex!.userId, from: params.db, accountManager: params.accountManager)
        }
        
        ownerCloudStorage = ownerAccount?.cloudStorage
        guard ownerCloudStorage != nil && ownerAccount != nil else {
            let message = "Could not obtain creds for v0 file: Assuming this means owning user is no longer on system."
            Log.error(message)
            finish(.errorResponse(.failure(
                .goneWithReason(message: message, .userRemoved))), params: params)
            return
        }
        
        // There is an unlikely race condition here -- two processes (within the same app, with the same deviceUUID) could be uploading the same file at the same time, both could upload, but only one would be able to create the Upload entry. I'm going to assume that this will not happen: That a single app/cilent will only upload the same file once at one time. (I used to create the Upload table entry first to avoid this race condition, but it's unlikely and leads to some locking issues-- see [1]).
        
        // Check to see if the file is present already-- i.e., if has been uploaded already.
        let key = UploadRepository.LookupKey.primaryKey(fileUUID: uploadRequest.fileUUID, userId: params.currentSignedInUser!.userId, deviceUUID: deviceUUID)
        let lookupResult = params.repos.upload.lookup(key: key, modelInit: Upload.init)
                
        switch lookupResult {
        case .found(let model):
            Log.info("File was already present: Not uploading again.")
            let upload = model as! Upload
            let response = UploadFileResponse()
            
            // Given that the file is still in the Upload table, there must be more files in the batch needing upload.
            response.allUploadsFinished = .uploadsNotFinished
            
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
        
        guard let mimeType = uploadRequest.mimeType else {
            let message = "No mimeType given!"
            finish(.errorMessage(message), params: params)
            return
        }
        
        if newFile {
            // Need to upload complete file.
            let cloudFileName = Filename.inCloud(deviceUUID:deviceUUID, fileUUID: uploadRequest.fileUUID, mimeType:uploadRequest.mimeType, fileVersion: 0)
            
            // This also does addUploadEntry.
            uploadV0File(cloudFileName: cloudFileName, mimeType: mimeType, creationDate: creationDate, todaysDate: todaysDate, params: params, ownerCloudStorage: ownerCloudStorage, ownerAccount: ownerAccount, uploadRequest: uploadRequest, deviceUUID: deviceUUID)
        }
        else {
            // Need to add the upload data to the UploadRepository only.
            guard let string = String(data: uploadRequest.data, encoding: .utf8) else {
                finish(.errorResponse(.failure(.message("Could not convert data to string"))), params: params)
                return
            }
            
            addUploadEntry(newFile: false, fileVersion: nil, creationDate: nil, todaysDate: nil, uploadedCheckSum: nil, cleanup: nil, params: params, uploadRequest: uploadRequest, deviceUUID: deviceUUID)
        }
    }
    
    private func uploadV0File(cloudFileName: String, mimeType: String, creationDate: Date, todaysDate: Date, params:RequestProcessingParameters, ownerCloudStorage: CloudStorage, ownerAccount: Account, uploadRequest:UploadFileRequest, deviceUUID: String) {
        // Lock will be held for the duration of the upload. Not the best, but don't have a better mechanism yet.
        
        Log.info("File being sent to cloud storage: \(cloudFileName)")

        let options = CloudStorageFileNameOptions(cloudFolderName: ownerAccount.cloudFolderName, mimeType: mimeType)
        
        let cleanup = Cleanup(cloudFileName: cloudFileName, options: options, ownerCloudStorage: ownerCloudStorage)
        
        ownerCloudStorage.uploadFile(cloudFileName:cloudFileName, data: uploadRequest.data, options:options) {[unowned self] result in
            switch result {
            case .success(let checkSum):
                Log.debug("File with checkSum \(checkSum) successfully uploaded!")
                
                self.addUploadEntry(newFile: true, fileVersion: 0, creationDate: creationDate, todaysDate: todaysDate, uploadedCheckSum: checkSum, cleanup: cleanup, params: params, uploadRequest: uploadRequest, deviceUUID: deviceUUID)

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
    
    // This also calls finishUploads
    private func addUploadEntry(newFile: Bool, fileVersion: FileVersionInt?, creationDate: Date?, todaysDate: Date?, uploadedCheckSum: String?, cleanup: Cleanup?, params:RequestProcessingParameters, uploadRequest: UploadFileRequest, deviceUUID: String) {
        
        let upload = Upload()
        upload.deviceUUID = deviceUUID
        upload.fileUUID = uploadRequest.fileUUID
        upload.mimeType = uploadRequest.mimeType
        upload.v0UploadFileVersion = newFile
        upload.sharingGroupUUID = uploadRequest.sharingGroupUUID
        upload.uploadCount = uploadRequest.uploadCount
        upload.uploadIndex = uploadRequest.uploadIndex

        // Waiting until now to check UploadRequest checksum because what's finally important is that the checksum before the upload is the same as that computed by the cloud storage service.
        var expectedCheckSum: String?
        expectedCheckSum = uploadRequest.checkSum?.lowercased()
        
#if DEBUG
        // Short-circuit check sum test in the case of load testing. 'cause it won't be right :).
        if let loadTesting = Configuration.server.loadTestingCloudStorage, loadTesting {
            expectedCheckSum = uploadedCheckSum
        }
#endif

        if let expectedCheckSum = expectedCheckSum {
            guard uploadedCheckSum?.lowercased() == expectedCheckSum else {
                let message = "Checksum after upload to cloud storage (\(String(describing: uploadedCheckSum)) is not the same as before upload \(String(describing: expectedCheckSum))."
                finish(.errorCleanup(message: message, cleanup: cleanup), params: params)
                return
            }
        }

        upload.lastUploadedCheckSum = uploadedCheckSum
    
        if let fileGroupUUID = uploadRequest.fileGroupUUID {
            guard fileVersion == 0 else {
                let message = "fileGroupUUID was given, but file version being uploaded (\(String(describing: fileVersion))) is not 0"
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
    
        upload.appMetaData = uploadRequest.appMetaData

        if newFile {
            upload.creationDate = creationDate
        }
    
        upload.updateDate = todaysDate
    
        let addUploadResult = params.repos.upload.retry {
            return params.repos.upload.add(upload: upload, fileInFileIndex: !newFile)
        }

        switch addUploadResult {
        case .success:
            guard let finishUploads = FinishUploads(sharingGroupUUID: uploadRequest.sharingGroupUUID, deviceUUID: deviceUUID, sharingGroupName: nil, params: params) else {
                finish(.errorCleanup(message: "Could not FinishUploads", cleanup: cleanup), params: params)
                return
            }
            
            let transferResponse = finishUploads.transfer()
            let response = UploadFileResponse()

            switch transferResponse {
            case .success:
                response.allUploadsFinished = .v0UploadsFinished
                
            case .allUploadsNotYetReceived:
                response.allUploadsFinished = .uploadsNotFinished
                
            case .deferredTransfer:
                response.allUploadsFinished = .vNUploadsTransferPending
                
            case .error(let response):
                params.completion(response)
                return
            }
            
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
