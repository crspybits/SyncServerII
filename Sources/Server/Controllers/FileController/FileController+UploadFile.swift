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

/* Algorithm:

1) Each upload will be N of M in a batch. Only when all of the uploads in a batch is received will an implict DoneUploads be carried out:
    1.1) v0 uploads
        * The entire initial file has been uploaded.
        * New records for each of these v0 file(s) are created in the FileIndex.
    1.2) vN uploads
        * Only a change is uploaded.
        * A DeferredUpload record is created for the batch.

2) DeferredUpload processing
    This is triggered after the DeferredUpload record is created in step 1.2)
        * It occurs asynchronously to client request processing
        * Only one instance of it will occur across possibly multiple server instances, so as to serialize the DeferredUpload processing.
        * It uses the ChangeResolvers to do conflict free application of the changes in the Upload records to the files.
 */

extension FileController {
    private struct Cleanup {
        let cloudFileName: String
        let options: CloudStorageFileNameOptions
        let ownerCloudStorage: CloudStorage
    }
    
    private enum Info {
        case success(response:UploadFileResponse, runner: RequestHandler.PostRequestRunner?)
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
                cleanup.ownerCloudStorage.deleteFile(cloudFileName: cleanup.cloudFileName, options: cleanup.options, completion: { _ in
                    Log.error(message)
                    params.completion(.failure(.message(message)))
                })
            }
            else {
                Log.error(message)
                params.completion(.failure(.message(message)))
            }
            
        case .success(response: let response, let runner):
            params.completion(.successWithRunner(response, runner: runner))
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
            finish(.errorMessage(message), params: params)
            return
        }
        
        guard let deviceUUID = params.deviceUUID else {
            let message = "Did not have deviceUUID"
            Log.error(message)
            finish(.errorMessage(message), params: params)
            return
        }
                
        guard sharingGroupSecurityCheck(sharingGroupUUID: uploadRequest.sharingGroupUUID, params: params) else {
            let message = "Failed in sharing group security check."
            Log.error(message)
            finish(.errorMessage(message), params: params)
            return
        }
        
        var existingFileInFileIndex:FileIndex?
        var existingFileGroupUUID: String?

        do {
            existingFileInFileIndex = try FileController.checkForExistingFile(params:params, sharingGroupUUID: uploadRequest.sharingGroupUUID, fileUUID:uploadRequest.fileUUID)
            
            // For an existing file, check to make sure that the request has no file group. It's an error to try to upload an existing file with a file group. E.g., this could be a client attempt to re-assign an existing file to a different file group, which is not allowed.
            if let _ = existingFileInFileIndex {
                guard uploadRequest.fileGroupUUID == nil else {
                    let message = "fileGroupUUID given for vN upload."
                    finish(.errorMessage(message), params: params)
                    return
                }
            }
        } catch (let error) {
            let message = "Could not lookup file in FileIndex: \(error)"
            finish(.errorMessage(message), params: params)
            return
        }
        
        // Content data for the initial v0 file or vN change.
        guard let fileContents = uploadRequest.data else {
            let message = "Could not get content data for file from request"
            Log.error(message)
            finish(.errorMessage(message), params: params)
            return
        }
        
        // This will be nil if (a) there is no existing file -- i.e., if this is an upload for a new file (v0) and if (b) an existing file doesn't have a fileGroupUUID.
        existingFileGroupUUID = existingFileInFileIndex?.fileGroupUUID
        
        // To send back to client.
        var creationDate:Date!
        
        let todaysDate = Date()
        
        var newFile = true
        if let existingFileInFileIndex = existingFileInFileIndex {
            guard uploadRequest.fileLabel == nil else {
                let message = "fileLabel given for a vN file."
                finish(.errorMessage(message), params: params)
                return
            }
            
            guard uploadRequest.appMetaData == nil else {
                let message = "App meta data only allowed with v0 of file."
                finish(.errorMessage(message), params: params)
                return
            }
        
            if existingFileInFileIndex.deleted {
                let message = "Attempt to upload an existing file, but it has already been deleted."
                finish(.errorResponse(.failure(
                    .goneWithReason(message: message, .fileRemovedOrRenamed))), params: params)
                return
            }
            
            guard let changeResolverName = existingFileInFileIndex.changeResolverName else {
                let message = "Attempt to upload change for vN file, but v0 had no change resolver."
                finish(.errorMessage(message), params: params)
                return
            }
            
            guard let resolverType = params.services.changeResolverManager.getResolverType(changeResolverName) else {
                let message = "Could not get change resolver type for: \(changeResolverName)"
                finish(.errorMessage(message), params: params)
                return
            }
            
            guard resolverType.valid(uploadContents: fileContents) else {
                let message = "Uploaded change is not valid for resolver type: \(changeResolverName)"
                finish(.errorMessage(message), params: params)
                return
            }
        
            newFile = false
            creationDate = existingFileInFileIndex.creationDate
        }
        else {            
            Log.info("Uploading first version of file.")
        
            // 8/9/17; I'm no longer going to use a date from the client for dates/times-- clients can lie.
            // https://github.com/crspybits/SyncServerII/issues/4
            creationDate = todaysDate
            
            guard let fileLabel = uploadRequest.fileLabel else {
                let message = "No fileLabel given for a v0 file."
                finish(.errorMessage(message), params: params)
                return
            }
            
            if let fileGroupUUID = uploadRequest.fileGroupUUID {
                // We also need to check all other fileLabel's for the file group-- we must not have a conflict.
                let fileIndexKey = FileIndexRepository.LookupKey.fileGroupUUIDAndFileLabel(fileGroupUUID: fileGroupUUID, fileLabel: fileLabel)
                let lookupFileIndex = params.repos.fileIndex.lookup(key: fileIndexKey, modelInit: FileIndex.init)
                switch lookupFileIndex {
                case .noObjectFound:
                    break
                case .found:
                    let message = "Already have fileLabel in FileIndex!"
                    finish(.errorMessage(message), params: params)
                    return
                case .error:
                    let message = "Error looking up fileLabel in FileIndex"
                    finish(.errorMessage(message), params: params)
                    return
                }
                
                let uploadKey = UploadRepository.LookupKey.fileGroupUUIDAndFileLabel(fileGroupUUID: fileGroupUUID, fileLabel: fileLabel)
                let uploadIndex = params.repos.upload.lookup(key: uploadKey, modelInit: Upload.init)
                switch uploadIndex {
                case .noObjectFound:
                    break
                case .found:
                    let message = "Already have fileLabel in Upload!"
                    finish(.errorMessage(message), params: params)
                    return
                case .error:
                    let message = "Error looking up fileLabel in Upload"
                    finish(.errorMessage(message), params: params)
                    return
                }
            }
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
            ownerAccount = FileController.getCreds(forUserId: existingFileInFileIndex!.userId, userRepo: params.repos.user, accountManager: params.services.accountManager, accountDelegate: params.accountDelegate)
        }
        
        ownerCloudStorage = ownerAccount?.cloudStorage(mock: params.services.mockStorage)
        guard ownerCloudStorage != nil && ownerAccount != nil else {
            let message = "Could not obtain creds for v0 file: Assuming this means owning user is no longer on system."
            Log.error(message)
            finish(.errorResponse(.failure(
                .goneWithReason(message: message, .userRemoved))), params: params)
            return
        }
        
        guard let signedInUserId = params.currentSignedInUser?.userId else {
            let message = "Could not get signed in user."
            finish(.errorMessage(message), params: params)
            return
        }
        
        // There is an unlikely race condition here -- two processes (within the same app, with the same deviceUUID) could be uploading the same file at the same time, both could upload, but only one would be able to create the Upload entry. I'm going to assume that this will not happen: That a single app/cilent will only upload the same file once at one time. (I used to create the Upload table entry first to avoid this race condition, but it's unlikely and leads to some locking issues-- see [1]).
        
        // Check to see if the file is present already-- i.e., if has been uploaded already.
        let key = UploadRepository.LookupKey.primaryKey(fileUUID: uploadRequest.fileUUID, userId: signedInUserId, deviceUUID: deviceUUID)
        let lookupResult = params.repos.upload.lookup(key: key, modelInit: Upload.init)
                
        switch lookupResult {
        case .found(let model):
            Log.info("File was already present: Not uploading again.")
            let upload = model as! Upload
            let response = UploadFileResponse()
            response.allUploadsFinished = .duplicateFileUpload
            
            // 12/27/17; Send the dates back down to the client. https://github.com/crspybits/SharedImages/issues/44
            response.creationDate = creationDate
            response.updateDate = upload.updateDate
            finish(.success(response: response, runner: nil), params: params)
            return
            
        case .noObjectFound:
            // Expected result
            break
            
        case .error(let message):
            finish(.errorMessage(message), params: params)
            return
        }
        
        if newFile {
            Log.debug("uploadRequest.changeResolverName: \(String(describing: uploadRequest.changeResolverName))")
            
            // Only new files can have change resolvers.
            if let resolverName = uploadRequest.changeResolverName {
                guard params.services.changeResolverManager.validResolver(resolverName) else {
                    let message = "Bad change resolver: \(resolverName)"
                    finish(.errorMessage(message), params: params)
                    return
                }
                
                // Test the initial data given. We have a change resolver, and want to ensure that the data works with the resolver. Otherwise, we can get into a situation where a vN change for the file gets uploaded and it fails because the v0 upload was invalid.
                guard let resolver = params.services.changeResolverManager.getResolverType(resolverName) else {
                    let message = "Could not get resolver for: \(resolverName)"
                    finish(.errorMessage(message), params: params)
                    return
                }
                
                guard resolver.validV0(contents: fileContents) else {
                    let message = "v0 contents for change resolver (\(resolverName)) were not valid."
                    finish(.errorMessage(message), params: params)
                    return
                }
            }
            
            guard let mimeType = uploadRequest.mimeType else {
                let message = "No mime type given with v0 of file."
                finish(.errorMessage(message), params: params)
                return
            }
            
            guard let _ = MimeType(rawValue: mimeType) else {
                let message = "Unknown mime type given: \(String(describing: uploadRequest.mimeType))"
                finish(.errorMessage(message), params: params)
                return
            }
        
            // Need to upload complete file.
            let cloudFileName = Filename.inCloud(deviceUUID:deviceUUID, fileUUID: uploadRequest.fileUUID, mimeType:mimeType, fileVersion: 0)
            
            // This also does addUploadEntry.
            uploadV0File(cloudFileName: cloudFileName, mimeType: mimeType, contents: fileContents, creationDate: creationDate, todaysDate: todaysDate, params: params, ownerCloudStorage: ownerCloudStorage, ownerAccount: ownerAccount, uploadRequest: uploadRequest, existingFileGroupUUID: existingFileGroupUUID, deviceUUID: deviceUUID, signedInUserId: signedInUserId)
        }
        else {
            guard uploadRequest.mimeType ==  nil else {
                let message = "Mime type given with vN of file."
                finish(.errorMessage(message), params: params)
                return
            }
            
            guard uploadRequest.changeResolverName == nil else {
                let message = "vN upload and there was a change resolver: \(String(describing: uploadRequest.changeResolverName))"
                finish(.errorMessage(message), params: params)
                return
            }
            
            addUploadEntry(newFile: false, creationDate: nil, todaysDate: todaysDate, uploadedCheckSum: nil, cleanup: nil, params: params, uploadRequest: uploadRequest, existingFileGroupUUID: existingFileGroupUUID, existingObjectType: existingFileInFileIndex?.objectType, deviceUUID: deviceUUID, uploadContents: fileContents, signedInUserId: signedInUserId)
        }
    }
    
    private func uploadV0File(cloudFileName: String, mimeType: String, contents: Data, creationDate: Date, todaysDate: Date, params:RequestProcessingParameters, ownerCloudStorage: CloudStorage, ownerAccount: Account, uploadRequest:UploadFileRequest, existingFileGroupUUID: String?, deviceUUID: String, signedInUserId: UserId) {
        
        Log.info("File being sent to cloud storage: \(cloudFileName)")

        let options = CloudStorageFileNameOptions(cloudFolderName: ownerAccount.cloudFolderName, mimeType: mimeType)
        
        let cleanup = Cleanup(cloudFileName: cloudFileName, options: options, ownerCloudStorage: ownerCloudStorage)
        
        ownerCloudStorage.uploadFile(cloudFileName:cloudFileName, data: contents, options:options) { [weak self] result in
            guard let self = self else { return }
            
            switch result {
            case .success(let checkSum):
                Log.debug("File with checkSum \(checkSum) successfully uploaded!")
                
                self.addUploadEntry(newFile: true, creationDate: creationDate, todaysDate: todaysDate, uploadedCheckSum: checkSum, cleanup: cleanup, params: params, uploadRequest: uploadRequest, existingFileGroupUUID: existingFileGroupUUID, existingObjectType: nil, deviceUUID: deviceUUID, signedInUserId: signedInUserId)

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
    
    // This also calls finishUploads. `newFile` true means v0 upload; false means vN upload.
    private func addUploadEntry(newFile: Bool, creationDate: Date?, todaysDate: Date?, uploadedCheckSum: String?, cleanup: Cleanup?, params:RequestProcessingParameters, uploadRequest: UploadFileRequest, existingFileGroupUUID: String?, existingObjectType: String?, deviceUUID: String, uploadContents: Data? = nil, signedInUserId: UserId) {
        
        if !newFile && uploadContents == nil {
            let message = "vN file and uploadContents were nil"
            finish(.errorCleanup(message: message, cleanup: cleanup), params: params)
            return
        }
        
        let upload = Upload()
        upload.deviceUUID = deviceUUID
        upload.fileUUID = uploadRequest.fileUUID
        upload.mimeType = uploadRequest.mimeType
        upload.state = newFile ? .v0UploadCompleteFile : .vNUploadFileChange
        upload.sharingGroupUUID = uploadRequest.sharingGroupUUID
        upload.uploadCount = uploadRequest.uploadCount
        upload.uploadIndex = uploadRequest.uploadIndex
        upload.uploadContents = uploadContents
        upload.changeResolverName = uploadRequest.changeResolverName

        // Waiting until now to check UploadRequest checksum because what's finally important is that the checksum before the upload is the same as that computed by the cloud storage service.
        let expectedCheckSum: String? = uploadRequest.checkSum?.lowercased()

        if newFile {
            upload.fileLabel = uploadRequest.fileLabel

            guard let expectedCheckSum = expectedCheckSum else {
                let message = "No check sum given for a v0 file."
                finish(.errorCleanup(message: message, cleanup: cleanup), params: params)
                return
            }

            guard uploadedCheckSum?.lowercased() == expectedCheckSum else {
                let message = "Checksum after upload to cloud storage \(String(describing: uploadedCheckSum)) is not the same as before upload \(String(describing: expectedCheckSum))."
                finish(.errorCleanup(message: message, cleanup: cleanup), params: params)
                return
            }
        }

        upload.lastUploadedCheckSum = uploadedCheckSum

        if let fileGroupUUID = uploadRequest.fileGroupUUID {
            guard newFile else {
                let message = "fileGroupUUID was given, but vN file being uploaded"
                finish(.errorCleanup(message: message, cleanup: cleanup), params: params)
                return
            }
            
            guard let _ = uploadRequest.objectType else {
                let message = "fileGroupUUID was given, but no object type given"
                finish(.errorCleanup(message: message, cleanup: cleanup), params: params)
                return
            }
            
            upload.fileGroupUUID = fileGroupUUID
        }
        else {
            upload.fileGroupUUID = existingFileGroupUUID
        }
        
        if let objectType = uploadRequest.objectType {
            guard newFile else {
                let message = "Object type given, but vN file being uploaded."
                finish(.errorCleanup(message: message, cleanup: cleanup), params: params)
                return
            }
            
            guard let _ = uploadRequest.fileGroupUUID else {
                let message = "Object type given for v0 upload, but file group not given."
                finish(.errorCleanup(message: message, cleanup: cleanup), params: params)
                return
            }
            
            upload.objectType = objectType
        }
        else {
            upload.objectType = existingObjectType
        }
    
        // We are using the current signed in user's id here (and not the effective user id) because we need a way of indexing or organizing the collection of files uploaded by a particular user.
        upload.userId = signedInUserId
    
        upload.appMetaData = uploadRequest.appMetaData?.contents

        if newFile {
            upload.creationDate = creationDate
        }
    
        upload.updateDate = todaysDate
        
        // 9/5/20; To deal with https://github.com/SyncServerII/ServerMain/issues/5 issue with parallel uploads, and in particular the `forUpdate: true`.
        let fileUploadsResult = params.repos.upload.uploadedFiles(forUserId: signedInUserId, sharingGroupUUID: uploadRequest.sharingGroupUUID, deviceUUID: deviceUUID, deferredUploadIdNull: true, forUpdate: true)
        switch fileUploadsResult {
        case .uploads:
            break
        case .error(let error):
            finish(.errorCleanup(message: "Could not get uploadedFiles: \(String(describing: error))", cleanup: cleanup), params: params)
            return
        }
    
        let addUploadResult = params.repos.upload.retry {
            return params.repos.upload.add(upload: upload, fileInFileIndex: !newFile)
        }

        let uploader = Uploader(services: params.services.uploaderServices, delegate: params.services)

        switch addUploadResult {
        case .success:
            guard let finishUploads = FinishUploadFiles(sharingGroupUUID: uploadRequest.sharingGroupUUID, deviceUUID: deviceUUID, uploader: uploader, params: params) else {
                finish(.errorCleanup(message: "Could not FinishUploads", cleanup: cleanup), params: params)
                return
            }
            
            let transferResponse: FinishUploadFiles.UploadsResponse
            do {
                transferResponse = try finishUploads.finish()
            } catch let error {
                finish(.errorCleanup(message: "Could not FinishUploads: \(error)", cleanup: cleanup), params: params)
                return
            }
            
            let response = UploadFileResponse()
            var postCommitRunner: RequestHandler.PostRequestRunner?
            
            switch transferResponse {
            case .success:
                response.allUploadsFinished = .v0UploadsFinished
                
            case .allUploadsNotYetReceived:
                response.allUploadsFinished = .uploadsNotFinished
                
            case .deferred(let deferredUploadId, let runner):
                response.allUploadsFinished = .vNUploadsTransferPending
                response.deferredUploadId = deferredUploadId
                postCommitRunner = runner
                
            case .error(let error):
                finish(.errorCleanup(message: "Could not FinishUploads: \(String(describing: error))", cleanup: cleanup), params: params)
                return
            }
            
            // 12/27/17; Send the dates back down to the client. https://github.com/crspybits/SharedImages/issues/44
            response.creationDate = creationDate
            response.updateDate = upload.updateDate
            finish(.success(response: response, runner: postCommitRunner), params: params)
            
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
