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
    
    enum UpdateMasterVersionResult : Error {
    case success
    case error(String)
    case masterVersionUpdate(MasterVersionInt)
    }
    
    private func updateMasterVersion(currentMasterVersion:MasterVersionInt, params:RequestProcessingParameters) -> UpdateMasterVersionResult {

        let currentMasterVersionObj = MasterVersion()
        currentMasterVersionObj.userId = params.currentSignedInUser!.userId
        currentMasterVersionObj.masterVersion = currentMasterVersion
        let updateMasterVersionResult = params.repos.masterVersion.updateToNext(current: currentMasterVersionObj)
        
        var result:UpdateMasterVersionResult!
        
        switch updateMasterVersionResult {
        case .success:
            result = UpdateMasterVersionResult.success
            
        case .error(let error):
            let message = "Failed lookup in MasterVersionRepository: \(error)"
            Log.error(message: message)
            result = UpdateMasterVersionResult.error(message)
            
        case .didNotMatchCurrentMasterVersion:
            
            getMasterVersion(params: params) { (error, masterVersion) in
                if error == nil {
                    result = UpdateMasterVersionResult.masterVersionUpdate(masterVersion!)
                }
                else {
                    result = UpdateMasterVersionResult.error("\(error!)")
                }
            }
        }
        
        return result
    }
    
    enum GetMasterVersionError : Error {
    case error(String)
    case noObjectFound
    }
    
    // Synchronous callback.
    private func getMasterVersion(params:RequestProcessingParameters, completion:(Error?, MasterVersionInt?)->()) {
        let key = MasterVersionRepository.LookupKey.userId(params.currentSignedInUser!.userId)
        let result = params.repos.masterVersion.lookup(key: key, modelInit: MasterVersion.init)
        
        switch result {
        case .error(let error):
            completion(GetMasterVersionError.error(error), nil)
            
        case .found(let model):
            let masterVersionObj = model as! MasterVersion
            completion(nil, masterVersionObj.masterVersion)
            
        case .noObjectFound:
            let errorMessage = "Master version record not found for userId: \(params.currentSignedInUser!.userId)"
            Log.error(message: errorMessage)
            completion(GetMasterVersionError.noObjectFound, nil)
        }
    }
    
    func uploadFile(params:RequestProcessingParameters) {
        guard let uploadRequest = params.request as? UploadFileRequest else {
            Log.error(message: "Did not receive UploadFileRequest")
            params.completion(nil)
            return
        }
        
        getMasterVersion(params: params) { error, masterVersion in
            if error != nil {
                Log.error(message: "Error: \(error)")
                params.completion(nil)
                return
            }

            if masterVersion != uploadRequest.masterVersion {
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
            
            Log.info(message: "File being sent to cloud storage: \(uploadRequest.cloudFileName(deviceUUID: params.deviceUUID!))")
            
            // I'm going to create the entry in the Upload repo first because otherwise, there's a race condition-- two processes (within the same app, with the same deviceUUID) could be uploading the same file at the same time, both could upload, but only one would be able to create the Upload entry. This way, the process of creating the Upload table entry will be the gatekeeper.
            
            let upload = Upload()
            upload.deviceUUID = params.deviceUUID
            upload.fileUUID = uploadRequest.fileUUID
            upload.fileVersion = uploadRequest.fileVersion
            upload.mimeType = uploadRequest.mimeType
            upload.state = .uploading
            upload.userId = params.currentSignedInUser!.userId
            upload.appMetaData = uploadRequest.appMetaData
            upload.cloudFolderName = uploadRequest.cloudFolderName
            
            if let uploadId = params.repos.upload.add(upload: upload) {
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
                            // TODO: *0* Need to remove the entry from the Upload repo. And remove the file from the cloud server.
                            Log.error(message: "Could not update UploadRepository: \(error)")
                            params.completion(nil)
                        }
                    }
                    else {
                        // TODO: *0* Need to remove the entry from the Upload repo. And could be useful to remove the file from the cloud server. It might be there.
                        Log.error(message: "Could not uploadSmallFile: error: \(error)")
                        params.completion(nil)
                    }
                }
            }
            else {
                // TODO: *0* It could be useful to attempt to remove the entry from the Upload repo. Just in case it's actually there.
                Log.error(message: "Could not add to UploadRepository")
                params.completion(nil)
            }
        }
    }
    
    func doneUploads(params:RequestProcessingParameters) {
        let lock = Lock(userId:params.currentSignedInUser!.userId, deviceUUID:params.deviceUUID!)
        switch params.repos.lock.lock(lock: lock) {
        case .success:
            break
        
        case .lockAlreadyHeld:
            Log.debug(message: "Error: Lock already held!")
            params.completion(nil)
            return
        
        case .errorRemovingStaleLocks, .modelValueWasNil, .otherError:
            Log.debug(message: "Error removing locks!")
            params.completion(nil)
            return
        }
        
        let result = doInitialDoneUploads(params: params)
        
        if !params.repos.lock.unlock(userId: params.currentSignedInUser!.userId) {
            Log.debug(message: "Error in unlock!")
            params.completion(nil)
            return
        }

        guard let (numberTransferred, uploadDeletions) = result else {
            Log.debug(message: "Error in doInitialDoneUploads!")
            // Don't do `params.completion(nil)` because we may not be passing back nil, i.e., for a master version update. The params.completion call was made in doInitialDoneUploads if needed.
            return
        }
        
        // Next: If there are any upload deletions, we need to actually do the file deletions. We are doing this *without* the lock held. I'm assuming it takes far longer to contact the cloud storage service than the other operations we are doing (e.g., mySQL operations).
        
        guard let googleCreds = params.creds as? GoogleCreds else {
            Log.error(message: "Could not obtain Google Creds")
            params.completion(nil)
            return
        }
        
        finishDoneUploads(uploadDeletions: uploadDeletions, params: params, googleCreds: googleCreds, numberTransferred: numberTransferred)
    }
    
    // This operates recursively so that we are not spinning off multiple threads when deleting > 1 file. This may make our processing dependent on stack depth. It does seem Swift makes use of tail recursion optimizations-- though not sure if this applies in the case of callbacks.
    private func finishDoneUploads(uploadDeletions:[FileInfo]?, params:RequestProcessingParameters, googleCreds:GoogleCreds, numberTransferred:Int32, numberErrorsDeletingFiles:Int32 = 0) {
    
        // Base case.
        if uploadDeletions == nil || uploadDeletions!.count == 0 {
            let response = DoneUploadsResponse()!
            
            if numberErrorsDeletingFiles > 0 {
                response.numberDeletionErrors = numberErrorsDeletingFiles
                Log.debug(message: "doneUploads.numberDeletionErrors: \(numberErrorsDeletingFiles)")
            }
            
            response.numberUploadsTransferred = numberTransferred
            Log.debug(message: "doneUploads.numberUploadsTransferred: \(numberTransferred)")
            
            params.completion(response)
            return
        }
        
        // Recursive case.
        let uploadDeletion = uploadDeletions![0]
        let cloudFileName = uploadDeletion.cloudFileName(deviceUUID: uploadDeletion.deviceUUID!)

        googleCreds.deleteFile(cloudFolderName: uploadDeletion.cloudFolderName!, cloudFileName: cloudFileName, mimeType: uploadDeletion.mimeType!) { error in
        
            let tail = (uploadDeletions!.count > 0) ?
                Array(uploadDeletions![1..<uploadDeletions!.count]) : nil
            var numberAdditionalErrors = 0
            
            if error != nil {
                // We could get into some odd situations here if we actually report an error by failing. Failing will cause a db transaction rollback. Which could mean we had some files deleted, but *all* of the entries would still be present in the FileIndex/Uploads directory. So, I'm not going to fail, but forge on. I'll report the errors in the DoneUploadsResponse message though.
                // TODO: *1* A better way to deal with this situation could be to use transactions at a finer grained level. Each deletion we do from Upload and FileIndex for an UploadDeletion could be in a transaction that we don't commit until the deletion succeeds with cloud storage.
                Log.warning(message: "Error occurred while deleting Google file: \(error!)")
                numberAdditionalErrors = 1
            }
            
            self.finishDoneUploads(uploadDeletions: tail, params: params, googleCreds: googleCreds, numberTransferred: numberTransferred, numberErrorsDeletingFiles: numberErrorsDeletingFiles + numberAdditionalErrors)
        }
    }
    
    private func doInitialDoneUploads(params:RequestProcessingParameters) -> (numberTransferred:Int32, uploadDeletions:[FileInfo]?)? {
        
        guard let doneUploadsRequest = params.request as? DoneUploadsRequest else {
            Log.error(message: "Did not receive DoneUploadsRequest")
            params.completion(nil)
            return nil
        }
        
#if DEBUG
        if doneUploadsRequest.testLockSync != nil {
            Log.info(message: "Starting sleep (testLockSync= \(doneUploadsRequest.testLockSync)).")
            Thread.sleep(forTimeInterval: TimeInterval(doneUploadsRequest.testLockSync!))
            Log.info(message: "Finished sleep (testLockSync= \(doneUploadsRequest.testLockSync)).")
        }
#endif

        var response:DoneUploadsResponse?
        
        let updateResult = updateMasterVersion(currentMasterVersion: doneUploadsRequest.masterVersion, params: params)
        switch updateResult {
        case .success:
            break
            
        case .masterVersionUpdate(let updatedMasterVersion):
            // [1]. 2/11/17. My initial thinking was that we would mark any uploads from this device as having a `toPurge` state, after having obtained an updated master version. However, that seems in opposition to my more recent idea of having a "GetUploads" endpoint which would indicate to a client which files were in an uploaded state. Perhaps what would be suitable is to provide clients with an endpoint to delete or flush files that are in an uploaded state, should they decide to do that.

            response = DoneUploadsResponse()
            response!.masterVersionUpdate = updatedMasterVersion
            params.completion(response)
            return nil
            
        case .error(let error):
            Log.error(message: "Failed on updateMasterVersion: \(error)")
            params.completion(nil)
            return nil
        }
        
        // Now, start the heavy lifting. This has to accomodate both file uploads, and upload deletions-- because these both need to alter the masterVersion (i.e., they change the file index).
        
        // 1) Transfer info to the FileIndex repository from Upload.
        let numberTransferred =
            params.repos.fileIndex.transferUploads(
                userId: params.currentSignedInUser!.userId,
                deviceUUID: params.deviceUUID!,
                upload: params.repos.upload)
        
        if numberTransferred == nil  {
            Log.error(message: "Failed on transfer to FileIndex!")
            params.completion(nil)
            return nil
        }
        
        // 2) Get the upload deletions, if any. This is somewhat tricky. What we need here are not just the entries from the `Upload` table-- we need the corresponding entries from FileIndex since those have the deviceUUID's that we need in order to correctly name the files in cloud storage.
        
        var uploadDeletions:[FileInfo]
        
        let uploadDeletionsResult = params.repos.upload.uploadedFiles(forUserId: params.currentSignedInUser!.userId, deviceUUID: params.deviceUUID!, andState: .toDeleteFromFileIndex)
        switch uploadDeletionsResult {
        case .uploads(let fileInfoArray):
            uploadDeletions = fileInfoArray

        case .error(let error):
            Log.error(message: "Failed to get upload deletions: \(error)")
            params.completion(nil)
            return nil
        }
        
        var primaryFileIndexKeys:[FileIndexRepository.LookupKey] = []
        
        for uploadDeletion in uploadDeletions {
            primaryFileIndexKeys += [.primaryKeys(userId: "\(params.currentSignedInUser!.userId!)", fileUUID: uploadDeletion.fileUUID)]
        }
        
        var fileIndexDeletions:[FileInfo]?
        
        if primaryFileIndexKeys.count > 0 {
            let fileIndexResult = params.repos.fileIndex.fileIndex(forKeys: primaryFileIndexKeys)
            switch fileIndexResult {
            case .fileIndex(let fileIndex):
                fileIndexDeletions = fileIndex
                
            case .error(let error):
                Log.error(message: "Failed to get fileIndex: \(error)")
                params.completion(nil)
                return nil
            }
        }
        
        // 3) Remove the corresponding records from the Upload repo-- this is specific to the userId and the deviceUUID.
        let filesForUserDevice = UploadRepository.LookupKey.filesForUserDevice(userId: params.currentSignedInUser!.userId, deviceUUID: params.deviceUUID!)
        
        switch params.repos.upload.remove(key: filesForUserDevice) {
        case .removed(let numberRows):
            if numberRows != numberTransferred {
                Log.error(message: "Number rows removed from Upload was \(numberRows) but should have been \(numberTransferred)!")
                params.completion(nil)
                return nil
            }
            
        case .error(_):
            Log.error(message: "Failed removing rows from Upload!")
            params.completion(nil)
            return nil
        }
        
        return (numberTransferred!, fileIndexDeletions)
    }
    
    func fileIndex(params:RequestProcessingParameters) {
        guard params.request is FileIndexRequest else {
            Log.error(message: "Did not receive FileIndexRequest")
            params.completion(nil)
            return
        }
        
        getMasterVersion(params: params) { (error, masterVersion) in
            if error != nil {
                params.completion(nil)
                return
            }
            
            let fileIndexResult = params.repos.fileIndex.fileIndex(forUserId: params.currentSignedInUser!.userId)

            switch fileIndexResult {
            case .fileIndex(let fileIndex):
                Log.info(message: "Number of entries in FileIndex: \(fileIndex.count)")
                let response = FileIndexResponse()!
                response.fileIndex = fileIndex
                response.masterVersion = masterVersion
                params.completion(response)
                
            case .error(let error):
                Log.error(message: "Error: \(error)")
                params.completion(nil)
                return
            }
        }
    }
    
    func downloadFile(params:RequestProcessingParameters) {
        guard let downloadRequest = params.request as? DownloadFileRequest else {
            Log.error(message: "Did not receive DownloadFileRequest")
            params.completion(nil)
            return
        }
        
        // TODO: *0* What would happen if someone else deletes the file as we we're downloading it? It seems a shame to hold a lock for the entire duration of the download, however.
        
        // TODO: *0* Related question: With transactions, if we just select from a particular row (i.e., for the master version for this user, as immediately below) does this result in a lock for the duration of the transaction? We could test for this by sleeping in the middle of the download below, and seeing if another request could delete the file at the same time. This should make a good test case for any mechanism that I come up with.

        getMasterVersion(params: params) { (error, masterVersion) in
            if error != nil {
                params.completion(nil)
                return
            }

            if masterVersion != downloadRequest.masterVersion {
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
            
            // First, lookup the file in the FileIndex. This does an important security check too-- makes sure our userId corresponds to the fileUUID.
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
            
            guard downloadRequest.fileVersion == fileIndexObj!.fileVersion else {
                Log.error(message: "Expected file version \(downloadRequest.fileVersion) was not the same as the actual version \(fileIndexObj!.fileVersion)")
                params.completion(nil)
                return
            }
            
            if fileIndexObj!.deleted! {
                Log.error(message: "The file you are trying to download has been deleted!")
                params.completion(nil)
                return
            }
            
            // TODO: *5*: Eventually, this should bypass the middle man and stream from the cloud storage service directly to the client.
            
            // TODO: *1* Hmmm. It seems odd to have the DownloadRequest actually give the cloudFolderName-- seems it should really be stored in the FileIndex. This is because the file, once stored, is really in a specific place in cloud storage.
            
            googleCreds.downloadSmallFile(
                cloudFolderName: fileIndexObj!.cloudFolderName, cloudFileName: fileIndexObj!.cloudFileName(deviceUUID:params.deviceUUID!), mimeType: fileIndexObj!.mimeType) { (data, error) in
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
    
    func getUploads(params:RequestProcessingParameters) {
        guard params.request is GetUploadsRequest else {
            Log.error(message: "Did not receive GetUploadsRequest")
            params.completion(nil)
            return
        }
        
        let uploadsResult = params.repos.upload.uploadedFiles(forUserId: params.currentSignedInUser!.userId, deviceUUID: params.deviceUUID!)

        switch uploadsResult {
        case .uploads(let uploads):
            let response = GetUploadsResponse()!
            response.uploads = uploads
            params.completion(response)
            
        case .error(let error):
            Log.error(message: "Error: \(error)")
            params.completion(nil)
            return
        }
    }
    
    func uploadDeletion(params:RequestProcessingParameters) {
        guard let uploadDeletionRequest = params.request as? UploadDeletionRequest else {
            Log.error(message: "Did not receive UploadDeletionRequest")
            params.completion(nil)
            return
        }
        
        getMasterVersion(params: params) { (error, masterVersion) in
            if error != nil {
                Log.error(message: "Error: \(error)")
                params.completion(nil)
                return
            }

            if masterVersion != uploadDeletionRequest.masterVersion {
                let response = UploadDeletionResponse()!
                response.masterVersionUpdate = masterVersion
                params.completion(response)
                return
            }
            
            // Check whether this fileUUID exists in the FileIndex.
            // Note that we don't explicitly need to additionally check if our userId matches that in the FileIndex-- the following lookup does that security check for us.

            let key = FileIndexRepository.LookupKey.primaryKeys(userId: "\(params.currentSignedInUser!.userId!)", fileUUID: uploadDeletionRequest.fileUUID)
            
            let lookupResult = params.repos.fileIndex.lookup(key: key, modelInit: FileIndex.init)
            
            var fileIndexObj:FileIndex!
            
            switch lookupResult {
            case .found(let modelObj):
                fileIndexObj = modelObj as? FileIndex
                if fileIndexObj == nil {
                    Log.error(message: "Could not convert model object to FileIndex")
                    params.completion(nil)
                    return
                }
                
            case .noObjectFound:
                Log.error(message: "Could not find file to delete in FileIndex")
                params.completion(nil)
                return
                
            case .error(let error):
                Log.error(message: "Error looking up file in FileIndex: \(error)")
                params.completion(nil)
                return
            }
            
            if fileIndexObj.fileVersion != uploadDeletionRequest.fileVersion {
                Log.error(message: "File index version is: \(fileIndexObj.fileVersion), but you asked to delete version: \(uploadDeletionRequest.fileVersion)")
                params.completion(nil)
                return
            }

#if DEBUG
            if let actualDeletion = uploadDeletionRequest.actualDeletion, actualDeletion != 0 {
                actuallyDeleteFileFromServer(key:key, uploadDeletionRequest:uploadDeletionRequest, fileIndexObj:fileIndexObj, params:params)
                return
            }
#endif

            // Create entry in Upload table.
            let upload = Upload()
            upload.fileUUID = uploadDeletionRequest.fileUUID
            upload.deviceUUID = params.deviceUUID
            upload.fileVersion = uploadDeletionRequest.fileVersion
            upload.state = .toDeleteFromFileIndex
            upload.userId = params.currentSignedInUser!.userId
            
            if let _ = params.repos.upload.add(upload: upload) {
                let response = UploadDeletionResponse()!
                params.completion(response)
                return
            }
            else {
                Log.error(message: "Unable to add UploadDeletion to Upload table")
                params.completion(nil)
                return
            }
        }
    }
    
#if DEBUG
    func actuallyDeleteFileFromServer(key:FileIndexRepository.LookupKey, uploadDeletionRequest: Filenaming, fileIndexObj:FileIndex, params:RequestProcessingParameters) {
    
        let result = params.repos.fileIndex.remove(key: key)
        switch result {
        case .removed(numberRows: let numberRows):
            if numberRows != 1 {
                Log.error(message: "Number of rows deleted \(numberRows) != 1")
                params.completion(nil)
                return
            }
            
        case .error(let error):
            Log.error(message: "Error deleting from FileIndex: \(error)")
            params.completion(nil)
            return
        }
        
        guard let googleCreds = params.creds as? GoogleCreds else {
            Log.error(message: "Error converting to GoogleCreds!")
            params.completion(nil)
            return
        }

        let cloudFileName = uploadDeletionRequest.cloudFileName(deviceUUID: fileIndexObj.deviceUUID!)

        googleCreds.deleteFile(cloudFolderName: fileIndexObj.cloudFolderName!, cloudFileName: cloudFileName, mimeType: fileIndexObj.mimeType!) { error in
            if error != nil  {
                Log.warning(message: "Error deleting file from cloud storage: \(error!)!")
                // I'm not going to fail if this fails-- this is for debugging and it's not a big deal. Drop through and report success.
            }
            
            let response = UploadDeletionResponse()!
            params.completion(response)
            return
        }
    }
#endif
}
