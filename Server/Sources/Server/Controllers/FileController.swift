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
    class func setup(db:Database) -> Bool {
        if case .failure(_) = UploadRepository(db).create() {
            return false
        }
        
        if case .failure(_) = FileIndexRepository(db).create() {
            return false
        }
        
        if case .failure(_) = LockRepository(db).create() {
            return false
        }
        
        return true
    }
    
    init() {
    }
    
    private func getMasterVersion(params:RequestProcessingParameters, completion:@escaping (ResponseMessage?)->(), carryOn:(_ masterVersion:MasterVersionInt)->()) {
        var errorMessage:String?

        let result = params.repos.masterVersion.lookup(key: .userId(params.currentSignedInUser!.userId), modelInit: MasterVersion.init)
        switch result {
        case .error(let error):
            errorMessage = "Failed lookup in MasterVersionRepository: \(error)"
            
        case .found(let object):
            let masterVersionObj = object as! MasterVersion
            carryOn(masterVersionObj.masterVersion)
            return
            
        case .noObjectFound:
            errorMessage = "Could not find MasterVersion"
        }

        Log.error(message: errorMessage!)
        completion(nil)
    }
    
    func upload(params:RequestProcessingParameters) {
    
        guard let uploadRequest = params.request as? UploadFileRequest else {
            Log.error(message: "Did not receive UploadFileRequest")
            params.completion(nil)
            return
        }
        
        getMasterVersion(params:params, completion: params.completion) { masterVersion in
            // Verify that uploadRequest.masterVersion is still the same as that stored in the database for this user. If not, inform the caller.
            if masterVersion != Int64(uploadRequest.masterVersion) {
                let response = UploadFileResponse()!
                response.masterVersionUpdate = masterVersion
                params.completion(response)
                return
            }
            
            guard let googleCreds = params.creds as? GoogleCreds else {
                Log.error(message: "Could not obtain Google Creds")
                params.completion(nil)
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
                    upload.fileVersion = uploadRequest.fileVersion
                    upload.mimeType = uploadRequest.mimeType
                    upload.state = .uploaded
                    upload.userId = params.currentSignedInUser!.userId
                    upload.appMetaData = uploadRequest.appMetaData
                    
                    if let _ = params.repos.upload.add(upload: upload) {
                        let response = UploadFileResponse()!
                        response.size = Int64(uploadRequest.data.count)
                        params.completion(response)
                    }
                    else {
                        Log.error(message: "Could not add to UploadRepository")
                        // TODO: The file has been uploaded to cloud service. But we don't have a record of it on the server. What do we do?
                        params.completion(nil)
                    }
                }
                else {
                    Log.error(message: "Could not uploadSmallFile: error: \(error)")
                    params.completion(nil)
                }
            }
        }
    }
    
    func doneUploads(params:RequestProcessingParameters) {
        
        guard let doneUploadsRequest = params.request as? DoneUploadsRequest else {
            Log.error(message: "Did not receive DoneUploadsRequest")
            params.completion(nil)
            return
        }
        
        // TODO: Hmmm. I'm not really certain if we need this Locking mechanism. We will have a transactionally based request shortly. Would any other process see the lock prior to us closing the transaction???
        
        let lock = Lock(userId:params.currentSignedInUser!.userId, deviceUUID:doneUploadsRequest.deviceUUID!)
        if !params.repos.lock.lock(lock: lock) {
            Log.error(message: "Could not obtain lock!")
            params.completion(nil)
            return
        }
        
#if DEBUG
        if doneUploadsRequest.testLockSync != nil {
            Log.info(message: "Starting sleep (testLockSync= \(doneUploadsRequest.testLockSync)).")
            Thread.sleep(forTimeInterval: TimeInterval(doneUploadsRequest.testLockSync!))
        }
#endif

        Log.info(message: "Finished locking (testLockSync= \(doneUploadsRequest.testLockSync)).")
        
        var response:DoneUploadsResponse?
        
        getMasterVersion(params:params, completion: { response in
            _ = params.repos.lock.unlock(userId: params.currentSignedInUser!.userId)
            params.completion(nil)
        },
        carryOn: { masterVersion in
            if masterVersion != Int64(doneUploadsRequest.masterVersion) {
                _ = params.repos.lock.unlock(userId: params.currentSignedInUser!.userId)
                
                // TODO: This is the point where we need to mark any previous uploads from this device as toPurge.
                
                response = DoneUploadsResponse()
                response!.masterVersionUpdate = masterVersion
                params.completion(response)
                return
            }

            // We've got the lock. Update the master version-- will help other devices avoid further uploading.
            if !params.repos.masterVersion.upsert(userId: params.currentSignedInUser!.userId) {
                _ = params.repos.lock.unlock(userId: params.currentSignedInUser!.userId)
                Log.error(message: "Failed updating master version!")
                params.completion(response)
                return
            }
            
            // Now, do the heavy lifting.
            
            // First, transfer info to the FileIndex repository from Upload.
            let numberTransferred =
                params.repos.fileIndex.transferUploads(
                    userId: params.currentSignedInUser!.userId,
                    deviceUUID: doneUploadsRequest.deviceUUID!,
                    upload: params.repos.upload)
            
            if numberTransferred == nil  {
                _ = params.repos.lock.unlock(userId: params.currentSignedInUser!.userId)
                Log.error(message: "Failed on transfer to FileIndex!")
                params.completion(nil)
                return
            }
            
            // Second, remove the corresponding records from the Upload repo.
            let filesForUser = UploadRepository.LookupKey.filesForUser(userId: params.currentSignedInUser!.userId, deviceUUID: doneUploadsRequest.deviceUUID!)
            
            switch params.repos.upload.remove(key: filesForUser) {
            case .removed(let numberRows):
                if numberRows != numberTransferred {
                    Log.error(message: "Number rows removed from Upload was \(numberRows) but should have been \(numberTransferred)!")
                    params.completion(nil)
                    return
                }
                
            case .error(_):
                Log.error(message: "Failed removing rows from Upload!")
                params.completion(nil)
                return
            }
            
            _ = params.repos.lock.unlock(userId: params.currentSignedInUser!.userId)
            
            response = DoneUploadsResponse()
            response!.numberUploadsTransferred = numberTransferred
            Log.debug(message: "doneUploads.numberUploadsTransferred: \(numberTransferred)")
            params.completion(response)
        })
    }
    
    func fileIndex(params:RequestProcessingParameters) {
        
        guard params.request is FileIndexRequest else {
            Log.error(message: "Did not receive FileIndexRequest")
            params.completion(nil)
            return
        }
        
        // TODO: Should make sure that the device UUID in the FileIndexRequest is actually associated with the user. (But, need DeviceUUIDRepository for that.).
        
        // TODO: The FileIndex serves as a kind of snapshot of the files on the server for the calling apps. We ought to hold the lock while we take the snapshot-- to make sure we're not getting a cross section of changes imposed by other apps.
        
        getMasterVersion(params:params, completion: params.completion) { masterVersion in
            let fileIndexResult = params.repos.fileIndex.fileIndex(forUserId: params.currentSignedInUser!.userId)
            switch fileIndexResult {
            case .fileIndex(let fileIndex):
                let response = FileIndexResponse()!
                response.fileIndex = fileIndex
                response.masterVersion = masterVersion
                params.completion(response)
                
            case .error(_):
                params.completion(nil)
            }
        }
    }
    
    func downloadFile(params:RequestProcessingParameters) {
        
        guard let downloadRequest = params.request as? DownloadFileRequest else {
            Log.error(message: "Did not receive DownloadFileRequest")
            params.completion(nil)
            return
        }
        
        // TODO: Should make sure that the device UUID in the FileIndexRequest is actually associated with the user. (But, need DeviceUUIDRepository for that.).

        getMasterVersion(params:params, completion: params.completion) { masterVersion in
            // Verify that downloadRequest.masterVersion is still the same as that stored in the database for this user. If not, inform the caller.
            if masterVersion != Int64(downloadRequest.masterVersion) {
                let response = DownloadFileResponse()!
                response.masterVersionUpdate = masterVersion
                params.completion(response)
                return
            }
            
            // TODO: Need to actually do the download!
        }
    }
}
