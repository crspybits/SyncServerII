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
        
        if case .failure(_) = FileIndexRepository.create() {
            return false
        }
        
        if case .failure(_) = LockRepository.create() {
            return false
        }
        
        return true
    }
    
    init() {
    }
    
    private func getMasterVersion(completion:@escaping (ResponseMessage?)->(), carryOn:(_ masterVersion:MasterVersionInt)->()) {
        var errorMessage:String?

        let result = MasterVersionRepository.lookup(key: .userId(SignedInUser.session.current!.userId), modelInit: MasterVersion.init)
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
    
    func upload(_ request: RequestMessage, creds:Creds?, profile:UserProfile?,
        completion:@escaping (ResponseMessage?)->()) {
    
        guard let uploadRequest = request as? UploadFileRequest else {
            Log.error(message: "Did not receive UploadFileRequest")
            completion(nil)
            return
        }
        
        getMasterVersion(completion: completion) { masterVersion in
            // Verify that uploadRequest.masterVersion is still the same as that stored in the database for this user. If not, inform the caller.
            if masterVersion != Int64(uploadRequest.masterVersion) {
                let response = UploadFileResponse()!
                response.masterVersionUpdate = masterVersion
                completion(response)
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
                    upload.fileVersion = uploadRequest.fileVersion
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
                        Log.error(message: "Could not add to UploadRepository")
                        // TODO: The file has been uploaded to cloud service. But we don't have a record of it on the server. What do we do?
                        completion(nil)
                    }
                }
                else {
                    Log.error(message: "Could not uploadSmallFile: error: \(error)")
                    completion(nil)
                }
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
        
        // TODO: Hmmm. I'm not really certain if we need this Locking mechanism. We will have a transactionally based request shortly. Would any other process see the lock prior to us closing the transaction???
        
        let lock = Lock(userId:SignedInUser.session.current!.userId, deviceUUID:doneUploadsRequest.deviceUUID!)
        if !LockRepository.lock(lock: lock) {
            Log.error(message: "Could not obtain lock!")
            completion(nil)
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
        
        getMasterVersion(completion: { response in
            _ = LockRepository.unlock(userId: SignedInUser.session.current!.userId)
            completion(nil)
        },
        carryOn: { masterVersion in
            if masterVersion != Int64(doneUploadsRequest.masterVersion) {
                _ = LockRepository.unlock(userId: SignedInUser.session.current!.userId)
                
                // TODO: This is the point where we need to mark any previous uploads from this device as toPurge.
                
                response = DoneUploadsResponse()
                response!.masterVersionUpdate = masterVersion
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
            
            // Now, do the heavy lifting.
            
            // First, transfer info to the FileIndex repository from Upload.
            let numberTransferred = FileIndexRepository.transferUploads(userId: SignedInUser.session.current!.userId, deviceUUID: doneUploadsRequest.deviceUUID!)
            
            if numberTransferred == nil  {
                _ = LockRepository.unlock(userId: SignedInUser.session.current!.userId)
                Log.error(message: "Failed on transfer to FileIndex!")
                completion(nil)
                return
            }
            
            // Second, remove the corresponding records from the Upload repo.
            let filesForUser = UploadRepository.LookupKey.filesForUser(userId: SignedInUser.session.current!.userId, deviceUUID: doneUploadsRequest.deviceUUID!)
            
            switch UploadRepository.remove(key: filesForUser) {
            case .removed(let numberRows):
                if numberRows != numberTransferred {
                    Log.error(message: "Number rows removed from Upload was \(numberRows) but should have been \(numberTransferred)!")
                    completion(nil)
                    return
                }
                
            case .error(_):
                Log.error(message: "Failed removing rows from Upload!")
                completion(nil)
                return
            }
            
            _ = LockRepository.unlock(userId: SignedInUser.session.current!.userId)
            
            response = DoneUploadsResponse()
            response!.numberUploadsTransferred = numberTransferred
            Log.debug(message: "doneUploads.numberUploadsTransferred: \(numberTransferred)")
            completion(response)
        })
    }
    
    func fileIndex(_ request: RequestMessage, creds:Creds?, profile:UserProfile?,
        completion:@escaping (ResponseMessage?)->()) {
        
        guard request is FileIndexRequest else {
            Log.error(message: "Did not receive FileIndexRequest")
            completion(nil)
            return
        }
        
        // TODO: Should make sure that the device UUID in the FileIndexRequest is actually associated with the user. (But, need DeviceUUIDRepository for that.).
        
        // TODO: The FileIndex serves as a kind of snapshot of the files on the server for the calling apps. We ought to hold the lock while we take the snapshot-- to make sure we're not getting a cross section of changes imposed by other apps.
        
        getMasterVersion(completion: completion) { masterVersion in
            let fileIndexResult = FileIndexRepository.fileIndex(forUserId: SignedInUser.session.current!.userId)
            switch fileIndexResult {
            case .fileIndex(let fileIndex):
                let response = FileIndexResponse()!
                response.fileIndex = fileIndex
                response.masterVersion = masterVersion
                completion(response)
                
            case .error(_):
                completion(nil)
            }
        }
    }
    
    func downloadFile(_ request: RequestMessage, creds:Creds?, profile:UserProfile?,
        completion:@escaping (ResponseMessage?)->()) {
        
        guard let downloadRequest = request as? DownloadFileRequest else {
            Log.error(message: "Did not receive DownloadFileRequest")
            completion(nil)
            return
        }
        
        // TODO: Should make sure that the device UUID in the FileIndexRequest is actually associated with the user. (But, need DeviceUUIDRepository for that.).

        getMasterVersion(completion: completion) { masterVersion in
            // Verify that downloadRequest.masterVersion is still the same as that stored in the database for this user. If not, inform the caller.
            if masterVersion != Int64(downloadRequest.masterVersion) {
                let response = DownloadFileResponse()!
                response.masterVersionUpdate = masterVersion
                completion(response)
                return
            }
            
            // TODO: Need to actually do the download!
        }
    }
}
