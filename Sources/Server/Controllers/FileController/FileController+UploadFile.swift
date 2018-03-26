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

extension FileController {
    private func success(params:RequestProcessingParameters, upload:Upload, creationDate:Date) {
        let response = UploadFileResponse()!
        response.size = Int64(upload.fileSizeBytes!)

        // 12/27/17; Send the dates back down to the client. https://github.com/crspybits/SharedImages/issues/44
        response.creationDate = creationDate
        response.updateDate = upload.updateDate
        
        params.completion(response)
    }
    
    func uploadFile(params:RequestProcessingParameters) {
        guard let uploadRequest = params.request as? UploadFileRequest else {
            Log.error("Did not receive UploadFileRequest")
            params.completion(nil)
            return
        }
        
        guard let _ = MimeType(rawValue: uploadRequest.mimeType) else {
            Log.error("Unknown mime type passed: \(uploadRequest.mimeType) (see SyncServer-Shared)")
            params.completion(nil)
            return
        }
        
        guard uploadRequest.fileVersion != nil else {
            Log.error("File version not given in upload request.")
            params.completion(nil)
            return
        }
        
        getMasterVersion(params: params) { error, masterVersion in
            if error != nil {
                Log.error("Error: \(String(describing: error))")
                params.completion(nil)
                return
            }

            if masterVersion != uploadRequest.masterVersion {
                let response = UploadFileResponse()!
                Log.warning("Master version update: \(String(describing: masterVersion))")
                response.masterVersionUpdate = masterVersion
                params.completion(response)
                return
            }
            
            guard let cloudStorage = params.effectiveOwningUserCreds as? CloudStorage else {
                Log.error("Could not obtain CloudStorage creds")
                params.completion(nil)
                return
            }
            
            // Check to see if (a) this file is already present in the FileIndex, and if so then (b) is the version being uploaded +1 from that in the FileIndex.
            var existingFileInFileIndex:FileIndex?
            do {
                existingFileInFileIndex = try FileController.checkForExistingFile(params:params, fileUUID:uploadRequest.fileUUID)
            } catch (let error) {
                Log.error("Could not lookup file in FileIndex: \(error)")
                params.completion(nil)
                return
            }
        
            guard UploadRepository.isValidAppMetaDataUpload(
                currServerAppMetaDataVersion: existingFileInFileIndex?.appMetaDataVersion,
                currServerAppMetaData:
                    existingFileInFileIndex?.appMetaData,
                optionalUpload:uploadRequest.appMetaData) else {
                Log.error("App meta data or version is not valid for upload.")
                params.completion(nil)
                return
            }
            
            // To send back to client.
            var creationDate:Date!
            
            let todaysDate = Date()
            
            var newFile = true
            if let existingFileInFileIndex = existingFileInFileIndex {
                if existingFileInFileIndex.deleted && (uploadRequest.undeleteServerFile == nil || uploadRequest.undeleteServerFile == 0) {
                    Log.error("Attempt to upload an existing file, but it has already been deleted.")
                    params.completion(nil)
                    return
                }
            
                newFile = false
                guard existingFileInFileIndex.fileVersion + 1 == uploadRequest.fileVersion else {
                    Log.error("File version being uploaded (\(uploadRequest.fileVersion)) is not +1 of current version: \(existingFileInFileIndex.fileVersion)")
                    params.completion(nil)
                    return
                }
                
                guard existingFileInFileIndex.mimeType == uploadRequest.mimeType else {
                    Log.error("File being uploaded(\(uploadRequest.mimeType)) doesn't have the same mime type as current version: \(existingFileInFileIndex.mimeType)")
                    params.completion(nil)
                    return
                }
                
                creationDate = existingFileInFileIndex.creationDate
            }
            else {
                if uploadRequest.undeleteServerFile != nil && uploadRequest.undeleteServerFile != 0  {
                    Log.error("Attempt to undelete a file but it's a new file!")
                    params.completion(nil)
                    return
                }
                
                // File isn't yet in the FileIndex-- must be a new file. Thus, must be version 0.
                guard uploadRequest.fileVersion == 0 else {
                    Log.error("File is new, but file version being uploaded (\(uploadRequest.fileVersion)) is not 0")
                    params.completion(nil)
                    return
                }
            
                // 8/9/17; I'm no longer going to use a date from the client for dates/times-- clients can lie.
                // https://github.com/crspybits/SyncServerII/issues/4
                creationDate = todaysDate
            }
            
            // TODO: *6* Need to have streaming data from client, and send streaming data up to Google Drive.
            
            // I'm going to create the entry in the Upload repo first because otherwise, there's a (albeit unlikely) race condition-- two processes (within the same app, with the same deviceUUID) could be uploading the same file at the same time, both could upload, but only one would be able to create the Upload entry. This way, the process of creating the Upload table entry will be the gatekeeper.
            
            let upload = Upload()
            upload.deviceUUID = params.deviceUUID
            upload.fileUUID = uploadRequest.fileUUID
            upload.fileVersion = uploadRequest.fileVersion
            upload.mimeType = uploadRequest.mimeType
            
            if uploadRequest.undeleteServerFile != nil && uploadRequest.undeleteServerFile != 0 {
                Log.info("Undeleting server file.")
                upload.state = .uploadingUndelete
            }
            else {
                upload.state = .uploadingFile
            }
            
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
                params.completion(nil)
                return
            }
            
            let cloudFileName = uploadRequest.cloudFileName(deviceUUID:params.deviceUUID!, mimeType: uploadRequest.mimeType)
            Log.info("File being sent to cloud storage: \(cloudFileName)")
            
            // Because we need this to get the cloudFolderName
            guard params.effectiveOwningUserCreds != nil else {
                Log.debug("No effectiveOwningUserCreds")
                params.completion(nil)
                return
            }
            
            let options = CloudStorageFileNameOptions(cloudFolderName: params.effectiveOwningUserCreds!.cloudFolderName, mimeType: uploadRequest.mimeType)
            
            cloudStorage.uploadFile(cloudFileName:cloudFileName, data: uploadRequest.data, options:options) {[unowned self] result in
                switch result {
                case .success(let fileSize):
                    upload.fileSizeBytes = Int64(fileSize)
                    
                    switch upload.state! {
                    case .uploadingFile:
                        upload.state = .uploadedFile
                        
                    case .uploadingUndelete:
                        upload.state = .uploadedUndelete
                        
                    default:
                        Log.error("Bad upload state: \(upload.state!)")
                        params.completion(nil)
                    }
                    
                    upload.uploadId = uploadId
                    if params.repos.upload.update(upload: upload, fileInFileIndex: !newFile) {
                        self.success(params: params, upload: upload, creationDate: creationDate)
                    }
                    else {
                        // TODO: *0* Need to remove the file from the cloud server.
                        Log.error("Could not update UploadRepository: \(String(describing: error))")
                        params.completion(nil)
                    }
                case .failure(let error):
                    // TODO: *0* It could be useful to remove the file from the cloud server. It might be there.
                    Log.error("Could not uploadFile: error: \(error)")
                    params.completion(nil)
                }
            }
        }
    }
}
