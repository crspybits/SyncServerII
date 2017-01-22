//
//  FileController.swift
//  Server
//
//  Created by Christopher Prince on 1/15/17.
//
//

import Foundation
import PerfectLib
import Credentials
import CredentialsGoogle

class FileController : ControllerProtocol {
    // Don't do this setup in init so that database initalizations don't have to be done per endpoint call.
    class func setup() -> Bool {
        if case .failure(_) = UploadRepository.create() {
            return false
        }
        return true
    }
    
    init() {
    }
    
    func upload(_ request: RequestMessage, creds:Creds?, profile:UserProfile?,
        completion:@escaping (ResponseMessage?)->()) {
    
        guard let uploadRequest = request as? UploadFileRequest else {
            Log.error(message: "Did not receive UploadFileRequest")
            completion(nil)
            return
        }
        
        // Verify that uploadRequest.masterVersion is still the same as that stored in the database for this user. If not, inform the caller.
        let result = MasterVersionRepository.lookup(key: .userId(SignedInUser.session.current!.userId), modelInit: MasterVersion.init)
        switch result {
        case .error(let error):
            Log.error(message: "Failed lookup in MasterVersionRepository: \(error)")
            completion(nil)
            return
            
        case .found(let object):
            let masterVersion = object as! MasterVersion
            if masterVersion.masterVersion != Int64(uploadRequest.masterVersion) {
                let response = UploadFileResponse()!
                response.masterVersionUpdate = masterVersion.masterVersion
                completion(response)
                return
            }
            
        case .noObjectFound:
            Log.error(message: "Could not find MasterVersion")
            completion(nil)
            return
        }
        
        guard let googleCreds = creds as? GoogleCreds else {
            Log.error(message: "Could not obtain Google Creds")
            completion(nil)
            return
        }
                
        // TODO: This needs to be generalized to enabling uploads to various kinds of cloud services. E.g., including Dropbox. Right now, it's just specific to Google Drive.
        
        // TODO: Need to have streaming data from client, and send streaming data up to Google Drive.
                
        googleCreds.uploadSmallFile(request: uploadRequest) { fileSize, error in
            if error == nil {
                let upload = Upload()
                upload.deviceUUID = uploadRequest.deviceUUID
                upload.fileSizeBytes = Int64(fileSize!)
                upload.fileUpload = true
                upload.fileUUID = uploadRequest.fileUUID
                upload.fileVersion = uploadRequest.fileVersionNumber
                upload.mimeType = uploadRequest.mimeType
                upload.state = .uploaded
                upload.userId = SignedInUser.session.current!.userId
                upload.appMetaData = uploadRequest.appMetaData
                
                if let _ = UploadRepository.add(upload: upload) {
                    let response = UploadFileResponse()!
                    response.size = Int64(uploadRequest.data.count)
                    completion(response)
                }
                else {
                    completion(nil)
                }
            }
            else {
                completion(nil)
            }
        }
    }
    
    func doneUploads(_ request: RequestMessage, creds:Creds?, profile:UserProfile?,
        completion:@escaping (ResponseMessage?)->()) {
        
        guard let doneUploadsRequest = request as? DoneUploadsRequest else {
            Log.error(message: "Did not receive DoneUploadsRequest")
            completion(nil)
            return
        }
        
        let lock = Lock(userId:SignedInUser.session.current!.userId, deviceUUID:doneUploadsRequest.deviceUUID!)
        if !LockRepository.lock(lock: lock) {
            Log.error(message: "Could not obtain lock!")
            completion(nil)
            return
        }
        
        var response:DoneUploadsResponse?
        var errorMessage:String?
        
        // Verify that doneUploadsRequest.masterVersion is still the same as that stored in the database for this user. If not, inform the caller.
        let result = MasterVersionRepository.lookup(key: .userId(SignedInUser.session.current!.userId), modelInit: MasterVersion.init)
        switch result {
        case .error(let error):
            errorMessage = "Failed lookup in MasterVersionRepository: \(error)"
            
        case .found(let object):
            let masterVersion = object as! MasterVersion
            if masterVersion.masterVersion != Int64(doneUploadsRequest.masterVersion) {
                response = DoneUploadsResponse()
                response!.masterVersionUpdate = masterVersion.masterVersion
            }
            
        case .noObjectFound:
            errorMessage = "Could not find MasterVersion"
        }

        if errorMessage != nil || response != nil {
            _ = LockRepository.unlock(userId: SignedInUser.session.current!.userId)
            if errorMessage != nil {
                Log.error(message: errorMessage!)
            }
            completion(response)
            return
        }
        
        // We've got the lock. Update the master version-- will help other devices avoid further uploading.
        if !MasterVersionRepository.upsert(userId: SignedInUser.session.current!.userId) {
            _ = LockRepository.unlock(userId: SignedInUser.session.current!.userId)
            Log.error(message: "Failed updating master version!")
            completion(response)
            return
        }
        
        // TODO: Now, do the heavy lifting. We're transfering info to the FileIndex repository.
    }
}
