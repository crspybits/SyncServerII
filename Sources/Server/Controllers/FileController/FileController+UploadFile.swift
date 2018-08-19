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
    private func success(params:RequestProcessingParameters, upload:Upload, creationDate:Date) {
        let response = UploadFileResponse()!
        response.size = Int64(upload.fileSizeBytes!)

        // 12/27/17; Send the dates back down to the client. https://github.com/crspybits/SharedImages/issues/44
        response.creationDate = creationDate
        response.updateDate = upload.updateDate
        
        params.completion(.success(response))
    }
    
    func uploadFile(params:RequestProcessingParameters) {
        guard let uploadRequest = params.request as? UploadFileRequest else {
            let message = "Did not receive UploadFileRequest"
            Log.error(message)
            params.completion(.failure(.message(message)))
            return
        }
        
        guard sharingGroupSecurityCheck(sharingGroupId: uploadRequest.sharingGroupId, params: params) else {
            let message = "Failed in sharing group security check."
            Log.error(message)
            params.completion(.failure(.message(message)))
            return
        }
        
        guard let consistentSharingGroups = checkSharingGroupConsistency(sharingGroupId: uploadRequest.sharingGroupId, params:params), consistentSharingGroups else {
            let message = "Inconsistent sharing groups."
            Log.error(message)
            params.completion(.failure(.message(message)))
            return
        }
        
        guard let _ = MimeType(rawValue: uploadRequest.mimeType) else {
            let message = "Unknown mime type passed: \(uploadRequest.mimeType) (see SyncServer-Shared)"
            Log.error(message)
            params.completion(.failure(.message(message)))
            return
        }
        
        guard uploadRequest.fileVersion != nil else {
            let message = "File version not given in upload request."
            Log.error(message)
            params.completion(.failure(.message(message)))
            return
        }
        
        Log.debug("uploadRequest.sharingGroupId: \(uploadRequest.sharingGroupId)")
        
        Controllers.getMasterVersion(sharingGroupId: uploadRequest.sharingGroupId, params: params) { error, masterVersion in
            if error != nil {
                let message = "Error: \(String(describing: error))"
                Log.error(message)
                params.completion(.failure(.message(message)))
                return
            }

            if masterVersion != uploadRequest.masterVersion {
                let response = UploadFileResponse()!
                Log.warning("Master version update: \(String(describing: masterVersion))")
                response.masterVersionUpdate = masterVersion
                params.completion(.success(response))
                return
            }
            
            // Check to see if (a) this file is already present in the FileIndex, and if so then (b) is the version being uploaded +1 from that in the FileIndex.
            var existingFileInFileIndex:FileIndex?
            do {
                existingFileInFileIndex = try FileController.checkForExistingFile(params:params, sharingGroupId: uploadRequest.sharingGroupId, fileUUID:uploadRequest.fileUUID)
            } catch (let error) {
                let message = "Could not lookup file in FileIndex: \(error)"
                Log.error(message)
                params.completion(.failure(.message(message)))
                return
            }
        
            guard UploadRepository.isValidAppMetaDataUpload(
                currServerAppMetaDataVersion: existingFileInFileIndex?.appMetaDataVersion,
                currServerAppMetaData:
                    existingFileInFileIndex?.appMetaData,
                optionalUpload:uploadRequest.appMetaData) else {
                let message = "App meta data or version is not valid for upload."
                Log.error(message)
                params.completion(.failure(.message(message)))
                return
            }
            
            // To send back to client.
            var creationDate:Date!
            
            let todaysDate = Date()
            
            var newFile = true
            if let existingFileInFileIndex = existingFileInFileIndex {
                if existingFileInFileIndex.deleted && (uploadRequest.undeleteServerFile == nil || uploadRequest.undeleteServerFile == 0) {
                    let message = "Attempt to upload an existing file, but it has already been deleted."
                    Log.error(message)
                    params.completion(.failure(.message(message)))
                    return
                }
            
                newFile = false
                guard existingFileInFileIndex.fileVersion + 1 == uploadRequest.fileVersion else {
                    let message = "File version being uploaded (\(uploadRequest.fileVersion)) is not +1 of current version: \(existingFileInFileIndex.fileVersion)"
                    Log.error(message)
                    params.completion(.failure(.message(message)))
                    return
                }
                
                guard existingFileInFileIndex.mimeType == uploadRequest.mimeType else {
                    let message = "File being uploaded(\(uploadRequest.mimeType)) doesn't have the same mime type as current version: \(existingFileInFileIndex.mimeType)"
                    Log.error(message)
                    params.completion(.failure(.message(message)))
                    return
                }
                
                creationDate = existingFileInFileIndex.creationDate
            }
            else {
                if uploadRequest.undeleteServerFile != nil && uploadRequest.undeleteServerFile != 0  {
                    let message = "Attempt to undelete a file but it's a new file!"
                    Log.error(message)
                    params.completion(.failure(.message(message)))
                    return
                }
                
                // File isn't yet in the FileIndex-- must be a new file. Thus, must be version 0.
                guard uploadRequest.fileVersion == 0 else {
                    let message = "File is new, but file version being uploaded (\(uploadRequest.fileVersion)) is not 0"
                    Log.error(message)
                    params.completion(.failure(.message(message)))
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
                ownerAccount = FileController.getCreds(forUserId: existingFileInFileIndex!.userId, from: params.db)
            }
            
            guard ownerAccount != nil else {
                let message = "No owning account!"
                Log.error(message)
                params.completion(.failure(.message(message)))
                return
            }
            
            ownerCloudStorage = ownerAccount as? CloudStorage
            guard ownerCloudStorage != nil && ownerAccount != nil else {
                let message = "Could not obtain creds for v0 file: Assuming this means owning user is no longer on system."
                Log.error(message)
                params.completion(.failure(.messageWithStatus(message, HTTPStatusCode.gone)))
                return
            }
            
            // I'm going to create the entry in the Upload repo first because otherwise, there's a (albeit unlikely) race condition-- two processes (within the same app, with the same deviceUUID) could be uploading the same file at the same time, both could upload, but only one would be able to create the Upload entry. This way, the process of creating the Upload table entry will be the gatekeeper.
            
            let upload = Upload()
            upload.deviceUUID = params.deviceUUID
            upload.fileUUID = uploadRequest.fileUUID
            upload.fileVersion = uploadRequest.fileVersion
            upload.mimeType = uploadRequest.mimeType
            upload.sharingGroupId = uploadRequest.sharingGroupId
            
            if let fileGroupUUID = uploadRequest.fileGroupUUID {
                guard uploadRequest.fileVersion == 0 else {
                    let message = "fileGroupUUID was given, but file version being uploaded (\(uploadRequest.fileVersion)) is not 0"
                    Log.error(message)
                    params.completion(.failure(.message(message)))
                    return
                }
                
                upload.fileGroupUUID = fileGroupUUID
            }
            
            if uploadRequest.undeleteServerFile != nil && uploadRequest.undeleteServerFile != 0 {
                Log.info("Undeleting server file.")
                upload.state = .uploadingUndelete
            }
            else {
                upload.state = .uploadingFile
            }
            
            // We are using the current signed in user's id here (and not the effective user id) because we need a way of indexing or organizing the collection of files uploaded by a particular user.
            upload.userId = params.currentSignedInUser!.userId
            
            upload.appMetaData = uploadRequest.appMetaData?.contents
            upload.appMetaDataVersion = uploadRequest.appMetaData?.version

            if newFile {
                upload.creationDate = creationDate
            }
            
            upload.updateDate = todaysDate
            
            // In order to allow for client retries (both due to error conditions, and when the master version is updated), I need to enable this call to not fail on a retry. However, I don't have to actually upload the file a second time to cloud storage. 
            // If we have the entry for the file in the Upload table, then we can be assume we did not get an error uploading the file to cloud storage. This is because if we did get an error uploading the file, we would have done a rollback on the Upload table `add`.
            
            var uploadId:Int64!
            var errorString:String?
            
            let addUploadResult = params.repos.upload.add(upload: upload, fileInFileIndex: !newFile)
            
            switch addUploadResult {
            case .success(uploadId: let id):
                uploadId = id
                
            case .duplicateEntry:
                // We don't have a fileSize-- but, let's return it for consistency sake.
                let key = UploadRepository.LookupKey.primaryKey(fileUUID: uploadRequest.fileUUID, userId: params.currentSignedInUser!.userId, deviceUUID: params.deviceUUID!)
                let lookupResult = params.repos.upload.lookup(key: key, modelInit: Upload.init)
                
                switch lookupResult {
                case .found(let model):
                    Log.info("File was already present: Not uploading again.")
                    let upload = model as! Upload
                    success(params: params, upload: upload, creationDate: creationDate)
                    return
                    
                case .noObjectFound:
                    errorString = "No object found!"
                    
                case .error(let error):
                    errorString = error
                }
                
            case .aModelValueWasNil:
                errorString = "A model value was nil!"
                
            case .otherError(let error):
                errorString = error
            }
            
            if errorString != nil {
                Log.error(errorString!)
                params.completion(.failure(.message(errorString!)))
                return
            }
            
            let cloudFileName = uploadRequest.cloudFileName(deviceUUID:params.deviceUUID!, mimeType: uploadRequest.mimeType)
            
            guard let mimeType = uploadRequest.mimeType else {
                let message = "No mimeType given!"
                Log.error(message)
                params.completion(.failure(.message(message)))
                return
            }
            
            Log.info("File being sent to cloud storage: \(cloudFileName)")

            let options = CloudStorageFileNameOptions(cloudFolderName: ownerAccount.cloudFolderName, mimeType: mimeType)
            
            ownerCloudStorage.uploadFile(cloudFileName:cloudFileName, data: uploadRequest.data, options:options) {[unowned self] result in
                switch result {
                case .success(let fileSize):
                    Log.debug("File with size \(fileSize) successfully uploaded!")
                    upload.fileSizeBytes = Int64(fileSize)
                    
                    switch upload.state! {
                    case .uploadingFile:
                        upload.state = .uploadedFile
                        
                    case .uploadingUndelete:
                        upload.state = .uploadedUndelete
                        
                    default:
                        let message = "Bad upload state: \(upload.state!)"
                        Log.error(message)
                        params.completion(.failure(.message(message)))
                    }
                    
                    upload.uploadId = uploadId
                    if params.repos.upload.update(upload: upload, fileInFileIndex: !newFile) {
                        self.success(params: params, upload: upload, creationDate: creationDate)
                    }
                    else {
                        // TODO: *0* Need to remove the file from the cloud server.
                        let message = "Could not update UploadRepository: \(String(describing: error))"
                        Log.error(message)
                        params.completion(.failure(.message(message)))
                    }
                case .failure(let error):
                    // TODO: *0* It could be useful to remove the file from the cloud server. It might be there.
                    let message = "Could not uploadFile: error: \(error)"
                    Log.error(message)
                    params.completion(.failure(.message(message)))
                }
            }
        }
    }
}
