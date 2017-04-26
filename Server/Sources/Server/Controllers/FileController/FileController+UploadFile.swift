//
//  FileController+UploadFile.swift
//  Server
//
//  Created by Christopher Prince on 3/22/17.
//
//

import Foundation
import PerfectLib

extension FileController {
    func uploadFile(params:RequestProcessingParameters) {
        guard let uploadRequest = params.request as? UploadFileRequest else {
            Log.error(message: "Did not receive UploadFileRequest")
            params.completion(nil)
            return
        }
        
        getMasterVersion(params: params) { error, masterVersion in
            if error != nil {
                Log.error(message: "Error: \(String(describing: error))")
                params.completion(nil)
                return
            }

            if masterVersion != uploadRequest.masterVersion {
                let response = UploadFileResponse()!
                Log.warning(message: "Master version update: \(String(describing: masterVersion))")
                response.masterVersionUpdate = masterVersion
                params.completion(response)
                return
            }
            
            // TODO: *3* Needs generalization for multiple cloud services.
            guard let googleCreds = params.effectiveOwningUserCreds as? GoogleCreds else {
                Log.error(message: "Could not obtain Google Creds")
                params.completion(nil)
                return
            }
                    
            // TODO: *5* This needs to be generalized to enabling uploads to various kinds of cloud services. E.g., including Dropbox. Right now, it's just specific to Google Drive.
            
            // TODO: *6* Need to have streaming data from client, and send streaming data up to Google Drive.
            
            // I'm going to create the entry in the Upload repo first because otherwise, there's a (albeit unlikely) race condition-- two processes (within the same app, with the same deviceUUID) could be uploading the same file at the same time, both could upload, but only one would be able to create the Upload entry. This way, the process of creating the Upload table entry will be the gatekeeper.
            
            let upload = Upload()
            upload.deviceUUID = params.deviceUUID
            upload.fileUUID = uploadRequest.fileUUID
            upload.fileVersion = uploadRequest.fileVersion
            upload.mimeType = uploadRequest.mimeType
            upload.state = .uploading
            upload.userId = params.currentSignedInUser!.userId
            upload.appMetaData = uploadRequest.appMetaData
            upload.cloudFolderName = uploadRequest.cloudFolderName
            
            // In order to allow for client retries (both due to error conditions, and when the master version is updated), I need to enable this call to not fail on a retry. However, I don't have to actually upload the file a second time to cloud storage. 
            // If we have the entry for the file in the Upload table, then we can be assume we did not get an error uploading the file to cloud storage. This is because if we did get an error uploading the file, we would have done a rollback on the Upload table `add`.
            
            var uploadId:Int64!
            var errorString:String?
            
            let addUploadResult = params.repos.upload.add(upload: upload)
            
            switch addUploadResult {
            case .success(uploadId: let id):
                uploadId = id
                
            case .duplicateEntry:
                // We don't have a fileSize-- but, let's return it for consistency sake.
                let key = UploadRepository.LookupKey.primaryKey(fileUUID: uploadRequest.fileUUID, userId: params.currentSignedInUser!.userId, deviceUUID: params.deviceUUID!)
                let lookupResult = params.repos.upload.lookup(key: key, modelInit: Upload.init)
                
                switch lookupResult {
                case .found(let model):
                    Log.info(message: "File was already present: Not uploading again.")
                    let upload = model as! Upload
                    let response = UploadFileResponse()!
                    response.size = Int64(upload.fileSizeBytes!)
                    params.completion(response)
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
                Log.error(message: errorString!)
                params.completion(nil)
                return
            }
            
            Log.info(message: "File being sent to cloud storage: \(uploadRequest.cloudFileName(deviceUUID: params.deviceUUID!))")
            
            googleCreds.uploadSmallFile(deviceUUID:params.deviceUUID!, request: uploadRequest) { fileSize, error in
                if error == nil {
                    upload.fileSizeBytes = Int64(fileSize!)
                    upload.state = .uploaded
                    upload.uploadId = uploadId
                    if params.repos.upload.update(upload: upload) {
                        let response = UploadFileResponse()!
                        response.size = Int64(fileSize!)
                        params.completion(response)
                    }
                    else {
                        // TODO: *0* Need to remove the file from the cloud server.
                        Log.error(message: "Could not update UploadRepository: \(String(describing: error))")
                        params.completion(nil)
                    }
                }
                else {
                    // TODO: *0* It could be useful to remove the file from the cloud server. It might be there.
                    Log.error(message: "Could not uploadSmallFile: error: \(String(describing: error))")
                    params.completion(nil)
                }
            }
        }
    }
}
