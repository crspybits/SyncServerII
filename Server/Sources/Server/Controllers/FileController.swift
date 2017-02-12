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
                    
            // TODO: *5* This needs to be generalized to enabling uploads to various kinds of cloud services. E.g., including Dropbox. Right now, it's just specific to Google Drive.
            
            // TODO: *6* Need to have streaming data from client, and send streaming data up to Google Drive.
            
            Log.info(message: "File being sent to cloud storage: \(uploadRequest.cloudFileName())")
            
            // I'm going to create the entry in the Upload repo first because otherwise, there's a race condition-- two processes (within the same app, with the same deviceUUID) could be uploading the same file at the same time, both could upload, but only one would be able to create the Upload entry. This way, the process of creating the Upload table entry will be the gatekeeper.
            
            let upload = Upload()
            upload.deviceUUID = uploadRequest.deviceUUID
            upload.fileUpload = true
            upload.fileUUID = uploadRequest.fileUUID
            upload.fileVersion = uploadRequest.fileVersion
            upload.mimeType = uploadRequest.mimeType
            upload.state = .uploading
            upload.userId = params.currentSignedInUser!.userId
            upload.appMetaData = uploadRequest.appMetaData
            
            if let uploadId = params.repos.upload.add(upload: upload) {
                googleCreds.uploadSmallFile(request: uploadRequest) { fileSize, error in
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
                            // TODO: *1* Need to remove the entry from the Upload repo. And remove the file from the cloud server.
                            Log.error(message: "Could not update UploadRepository: \(error)")
                            params.completion(nil)
                        }
                    }
                    else {
                        // TODO: *1* Need to remove the entry from the Upload repo. And could be useful to remove the file from the cloud server. It might be there.
                        Log.error(message: "Could not uploadSmallFile: error: \(error)")
                        params.completion(nil)
                    }
                }
            }
            else {
                // TODO: *1* It could be useful to attempt to remove the entry from the Upload repo. Just in case it's actually there.
                Log.error(message: "Could not add to UploadRepository")
                params.completion(nil)
            }
        }
    }
    
    func doneUploads(params:RequestProcessingParameters) {
        
        guard let doneUploadsRequest = params.request as? DoneUploadsRequest else {
            Log.error(message: "Did not receive DoneUploadsRequest")
            params.completion(nil)
            return
        }
        
        let lock = Lock(userId:params.currentSignedInUser!.userId, deviceUUID:doneUploadsRequest.deviceUUID!)
        switch params.repos.lock.lock(lock: lock) {
        case .success:
            Log.info(message: "Sucessfully obtained lock!!")
            break
        
        // 2/11/16. We should never get here. With the transaction support just added, when server thread/request X attempts to obtain a lock and (a) another server thread/request (Y) has previously started a transaction, and (b) has obtained a lock in this manner, but (c) not ended the transaction, (d) a *transaction-level* lock will be obtained on the lock table row by request Y. Request X will be *blocked* in the server until the request Y completes its transaction.
        case .lockAlreadyHeld:
            Log.error(message: "Error: Lock already held.")
            params.completion(nil)
            return
        
        case .errorRemovingStaleLocks, .modelValueWasNil, .otherError:
            Log.error(message: "Error obtaining lock!")
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
                
                // [1]. 2/11/17. My initial thinking was that we would mark any uploads from this device as having a `toPurge` state, after having obtained an updated master version. However, that seems in opposition to my more recent idea of having a "GetUploads" endpoint which would indicate to a client which files were in an uploaded state. Perhaps what would be suitable is to provide clients with an endpoint to delete or flush files that are in an uploaded state, should they decide to do that.

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
            let filesForUserDevice = UploadRepository.LookupKey.filesForUserDevice(userId: params.currentSignedInUser!.userId, deviceUUID: doneUploadsRequest.deviceUUID!)
            
            switch params.repos.upload.remove(key: filesForUserDevice) {
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
            
            // TODO: *1* Why don't I have a check for errors here?
            _ = params.repos.lock.unlock(userId: params.currentSignedInUser!.userId)
            Log.info(message: "Unlocked lock.")

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
        
        // TODO: *1* Should make sure that the device UUID in the FileIndexRequest is actually associated with the user. (But, need DeviceUUIDRepository for that.).
        
        // TODO: *1* The FileIndex serves as a kind of snapshot of the files on the server for the calling apps. We ought to hold the lock while we take the snapshot-- to make sure we're not getting a cross section of changes imposed by other apps.
        
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
        
        // TODO: *1* Should make sure that the device UUID in the FileIndexRequest is actually associated with the user. (But, need DeviceUUIDRepository for that.).

        getMasterVersion(params:params, completion: params.completion) { masterVersion in
            // Verify that downloadRequest.masterVersion is still the same as that stored in the database for this user. If not, inform the caller.
            if masterVersion != Int64(downloadRequest.masterVersion) {
                let response = DownloadFileResponse()!
                response.masterVersionUpdate = masterVersion
                params.completion(response)
                return
            }

            // TODO: *5* Generalize this to use other cloud storage services.
            guard let googleCreds = params.creds as? GoogleCreds else {
                Log.error(message: "Could not obtain Google Creds")
                params.completion(nil)
                return
            }
            
            // Need to get the file from the cloud storage service:
            
            // First, lookup the file in the FileIndex
            let key = FileIndexRepository.LookupKey.primaryKeys(userId: "\(params.currentSignedInUser!.userId!)", fileUUID: downloadRequest.fileUUID)
            
            let lookupResult = params.repos.fileIndex.lookup(key: key, modelInit: FileIndex.init)
            
            var fileIndexObj:FileIndex?
            
            switch lookupResult {
            case .found(let modelObj):
                fileIndexObj = modelObj as? FileIndex
                if fileIndexObj == nil {
                    Log.error(message: "Could not convert model object to FileIndex")
                    params.completion(nil)
                    return
                }
                
            case .noObjectFound:
                Log.error(message: "Could not find file in FileIndex")
                params.completion(nil)
                return
                
            case .error(let error):
                Log.error(message: "Error looking up file in FileIndex: \(error)")
                params.completion(nil)
                return
            }
            
            // TODO: *5*: Eventually, this should bypass the middle man and stream from the cloud storage service directly to the client.
            
            // TODO: *1* Hmmm. It seems odd to have the DownloadRequest actually give the cloudFolderName-- seems it should really be stored in the FileIndex.
            
            googleCreds.downloadSmallFile(cloudFolderName: downloadRequest.cloudFolderName, cloudFileName: fileIndexObj!.cloudFileName(), mimeType: fileIndexObj!.mimeType) { (data, error) in
                if error == nil {
                    if Int64(data!.count) != fileIndexObj!.fileSizeBytes {
                        Log.error(message: "Actual file size \(data!.count) was not the same as that expected \(fileIndexObj!.fileSizeBytes)")
                        params.completion(nil)
                        return
                    }
                    
                    let response = DownloadFileResponse()!
                    response.appMetaData = fileIndexObj!.appMetaData
                    response.data = data!
                    response.fileSizeBytes = Int64(data!.count)
                    
                    params.completion(response)
                    return
                }
                else {
                    Log.error(message: "Failed downloading file: \(error)")
                    params.completion(nil)
                    return
                }
            }            
        }
    }
}
