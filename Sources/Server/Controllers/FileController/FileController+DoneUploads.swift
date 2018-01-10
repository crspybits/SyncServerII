//
//  FileController+DoneUploads.swift
//  Server
//
//  Created by Christopher Prince on 3/22/17.
//
//

import Foundation
import PerfectThread
import Dispatch
import LoggerAPI
import SyncServerShared

extension FileController {
    // Returns nil on an error.
    private func getFileIndexEntries(forUploadFiles uploadFiles:[FileInfo], params:RequestProcessingParameters) -> [FileInfo]? {
        var primaryFileIndexKeys = [FileIndexRepository.LookupKey]()
    
        for uploadFile in uploadFiles {
            // 12/1/17; Up until today, I was using the params.currentSignedInUser!.userId in here and not the effective user id. Thus, when sharing users did an upload deletion, the files got deleted from the file index, but didn't get deleted from cloud storage.
            primaryFileIndexKeys += [.primaryKeys(userId: "\(params.currentSignedInUser!.effectiveOwningUserId)", fileUUID: uploadFile.fileUUID)]
        }
    
        var fileIndexObjs = [FileInfo]()
    
        if primaryFileIndexKeys.count > 0 {
            let fileIndexResult = params.repos.fileIndex.fileIndex(forKeys: primaryFileIndexKeys)
            switch fileIndexResult {
            case .fileIndex(let fileIndex):
                fileIndexObjs = fileIndex
    
            case .error(let error):
                Log.error("Failed to get fileIndex: \(error)")
                return nil
            }
        }
        
        return fileIndexObjs
    }
    
    // staleVersionsToDelete gives info, if any, on files that we're uploading new versions of.
    private func doInitialDoneUploads(params:RequestProcessingParameters) -> (numberTransferred:Int32, uploadDeletions:[FileInfo]?, staleVersionsToDelete:[FileInfo]?)? {
        
        guard let doneUploadsRequest = params.request as? DoneUploadsRequest else {
            Log.error("Did not receive DoneUploadsRequest")
            params.completion(nil)
            return nil
        }
        
#if DEBUG
        if doneUploadsRequest.testLockSync != nil {
            Log.info("Starting sleep (testLockSync= \(String(describing: doneUploadsRequest.testLockSync))).")
            Thread.sleep(forTimeInterval: TimeInterval(doneUploadsRequest.testLockSync!))
            Log.info("Finished sleep (testLockSync= \(String(describing: doneUploadsRequest.testLockSync))).")
        }
#endif

        var response:DoneUploadsResponse?
        
        let updateResult = updateMasterVersion(currentMasterVersion: doneUploadsRequest.masterVersion, params: params)
        switch updateResult {
        case .success:
            break
            
        case .masterVersionUpdate(let updatedMasterVersion):
            // [1]. 2/11/17. My initial thinking was that we would mark any uploads from this device as having a `toPurge` state, after having obtained an updated master version. However, that seems in opposition to my more recent idea of having a "GetUploads" endpoint which would indicate to a client which files were in an uploaded state. Perhaps what would be suitable is to provide clients with an endpoint to delete or flush files that are in an uploaded state, should they decide to do that.
            Log.warning("Master version update: \(updatedMasterVersion)")
            response = DoneUploadsResponse()
            response!.masterVersionUpdate = updatedMasterVersion
            params.completion(response)
            return nil
            
        case .error(let error):
            Log.error("Failed on updateMasterVersion: \(error)")
            params.completion(nil)
            return nil
        }
        
        // Now, start the heavy lifting. This has to accomodate both file uploads, and upload deletions-- because these both need to alter the masterVersion (i.e., they change the file index).
        
        // 1) See if any of the file uploads are for file versions > 0. Later, we'll have to delete stale versions of the file(s) in cloud storage if so.
        // 2) Get the upload deletions, if any.
        
        var staleVersionsFromUploads:[FileInfo]
        var uploadDeletions:[FileInfo]
        
        let fileUploadsResult = params.repos.upload.uploadedFiles(forUserId: params.currentSignedInUser!.userId, deviceUUID: params.deviceUUID!)
        switch fileUploadsResult {
        case .uploads(let fileInfoArray):
            Log.debug("fileInfoArray.count for file uploads and upload deletions: \(fileInfoArray.count)")
            // 1) Filter out uploaded files with versions > 0 -- for the stale file versions.
            staleVersionsFromUploads = fileInfoArray.filter({$0.fileVersion > 0 && !$0.deleted})
            
            // 2) Filter out upload deletions
            uploadDeletions = fileInfoArray.filter({$0.deleted})

        case .error(let error):
            Log.error("Failed to get file uploads: \(error)")
            params.completion(nil)
            return nil
        }

        // Now, map the upload objects found to the file index. What we need here are not just the entries from the `Upload` table-- we need the corresponding entries from FileIndex since those have the deviceUUID's that we need in order to correctly name the files in cloud storage.
        guard let staleVersionsToDelete = getFileIndexEntries(forUploadFiles: staleVersionsFromUploads, params:params) else {
            params.completion(nil)
            return nil
        }
        
        guard let fileIndexDeletions = getFileIndexEntries(forUploadFiles: uploadDeletions, params:params) else {
            params.completion(nil)
            return nil
        }
        
        // 3) Transfer info to the FileIndex repository from Upload.
        let numberTransferred =
            params.repos.fileIndex.transferUploads(uploadUserId: params.currentSignedInUser!.userId, owningUserId: params.currentSignedInUser!.effectiveOwningUserId,
                uploadingDeviceUUID: params.deviceUUID!,
                uploadRepo: params.repos.upload)
        
        if numberTransferred == nil  {
            Log.error("Failed on transfer to FileIndex!")
            params.completion(nil)
            return nil
        }
        
        // 4) Remove the corresponding records from the Upload repo-- this is specific to the userId and the deviceUUID.
        let filesForUserDevice = UploadRepository.LookupKey.filesForUserDevice(userId: params.currentSignedInUser!.userId, deviceUUID: params.deviceUUID!)
        
        // 5/28/17; I just got an error on this: 
        // [ERR] Number rows removed from Upload was 10 but should have been Optional(9)!
        // How could this happen?
        
        switch params.repos.upload.remove(key: filesForUserDevice) {
        case .removed(let numberRows):
            if numberRows != numberTransferred {
                Log.error("Number rows removed from Upload was \(numberRows) but should have been \(String(describing: numberTransferred))!")
                params.completion(nil)
                return nil
            }
            
        case .error(_):
            Log.error("Failed removing rows from Upload!")
            params.completion(nil)
            return nil
        }
        
        return (numberTransferred!, fileIndexDeletions, staleVersionsToDelete)
    }
    
    enum UpdateMasterVersionResult : Error {
    case success
    case error(String)
    case masterVersionUpdate(MasterVersionInt)
    }
    
    private func updateMasterVersion(currentMasterVersion:MasterVersionInt, params:RequestProcessingParameters) -> UpdateMasterVersionResult {

        let currentMasterVersionObj = MasterVersion()
        
        // Note the use of `effectiveOwningUserId`: The master version reflects owning user data, not a sharing user.
        currentMasterVersionObj.userId = params.currentSignedInUser!.effectiveOwningUserId
        
        currentMasterVersionObj.masterVersion = currentMasterVersion
        let updateMasterVersionResult = params.repos.masterVersion.updateToNext(current: currentMasterVersionObj)
        
        var result:UpdateMasterVersionResult!
        
        switch updateMasterVersionResult {
        case .success:
            result = UpdateMasterVersionResult.success
            
        case .error(let error):
            let message = "Failed lookup in MasterVersionRepository: \(error)"
            Log.error(message)
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
    
    func doneUploads(params:RequestProcessingParameters) {
        // We are locking the owning user's collection of data, and so use `effectiveOwningUserId`.
        let lock = Lock(userId:params.currentSignedInUser!.effectiveOwningUserId, deviceUUID:params.deviceUUID!)
        switch params.repos.lock.lock(lock: lock) {
        case .success:
            break
        
        case .lockAlreadyHeld:
            Log.debug("Error: Lock already held!")
            params.completion(nil)
            return
        
        case .errorRemovingStaleLocks, .modelValueWasNil, .otherError:
            Log.debug("Error removing locks!")
            params.completion(nil)
            return
        }
        
        let result = doInitialDoneUploads(params: params)
        
        if !params.repos.lock.unlock(userId: params.currentSignedInUser!.effectiveOwningUserId) {
            Log.debug("Error in unlock!")
            params.completion(nil)
            return
        }

        guard let (numberTransferred, uploadDeletions, staleVersionsToDelete) = result else {
            Log.error("Error in doInitialDoneUploads!")
            // Don't do `params.completion(nil)` because we may not be passing back nil, i.e., for a master version update. The params.completion call was made in doInitialDoneUploads if needed.
            return
        }
        
        // Next: If there are any upload deletions, we need to actually do the file deletions. We are doing this *without* the lock held. I'm assuming it takes far longer to contact the cloud storage service than the other operations we are doing (e.g., mySQL operations).
        
        guard let cloudStorageCreds = params.effectiveOwningUserCreds as? CloudStorage else {
            Log.error("Could not obtain CloudStorage Creds")
            params.completion(nil)
            return
        }
        
        var cloudDeletions = [FileInfo]()
        if let uploadDeletions = uploadDeletions {
            cloudDeletions += uploadDeletions
        }
        if let staleVersionsToDelete = staleVersionsToDelete {
            cloudDeletions += staleVersionsToDelete
        }
        
        if cloudDeletions.count == 0  {
            let response = DoneUploadsResponse()!
            response.numberUploadsTransferred = numberTransferred
            Log.debug("no upload deletions or stale file versions: doneUploads.numberUploadsTransferred: \(numberTransferred)")
            params.completion(response)
            return
        }
        
        let async = AsyncTailRecursion()
        async.start {
            self.finishDoneUploads(cloudDeletions: cloudDeletions, params: params, cloudStorageCreds: cloudStorageCreds, numberTransferred: numberTransferred, async:async)
        }
    }

     private func finishDoneUploads(cloudDeletions:[FileInfo], params:RequestProcessingParameters, cloudStorageCreds:CloudStorage, numberTransferred:Int32, async:AsyncTailRecursion, numberErrorsDeletingFiles:Int32 = 0) {
    
        // Base case.
        if cloudDeletions.count == 0 {
            let response = DoneUploadsResponse()!
            
            if numberErrorsDeletingFiles > 0 {
                response.numberDeletionErrors = numberErrorsDeletingFiles
                Log.debug("doneUploads.numberDeletionErrors: \(numberErrorsDeletingFiles)")
            }
            
            response.numberUploadsTransferred = numberTransferred
            Log.debug("base case: doneUploads.numberUploadsTransferred: \(numberTransferred)")
            params.completion(response)
            async.done()
            return
        }
        
        // Recursive case.
        let cloudDeletion = cloudDeletions[0]
        let cloudFileName = cloudDeletion.cloudFileName(deviceUUID: cloudDeletion.deviceUUID!)

        Log.info("Deleting file: \(cloudFileName)")
        
        let options = CloudStorageFileNameOptions(cloudFolderName: cloudDeletion.cloudFolderName!, mimeType: cloudDeletion.mimeType!)
        
        cloudStorageCreds.deleteFile(cloudFileName: cloudFileName, options: options) { error in

            let tail = (cloudDeletions.count > 0) ?
                Array(cloudDeletions[1..<cloudDeletions.count]) : []
            var numberAdditionalErrors:Int32 = 0
            
            if error != nil {
                // We could get into some odd situations here if we actually report an error by failing. Failing will cause a db transaction rollback. Which could mean we had some files deleted, but *all* of the entries would still be present in the FileIndex/Uploads directory. So, I'm not going to fail, but forge on. I'll report the errors in the DoneUploadsResponse message though.
                // TODO: *1* A better way to deal with this situation could be to use transactions at a finer grained level. Each deletion we do from Upload and FileIndex for an UploadDeletion could be in a transaction that we don't commit until the deletion succeeds with cloud storage.
                Log.warning("Error occurred while deleting Google file: \(error!)")
                numberAdditionalErrors = 1
            }
            
            async.next() {
                self.finishDoneUploads(cloudDeletions: tail, params: params, cloudStorageCreds: cloudStorageCreds, numberTransferred: numberTransferred, async:async, numberErrorsDeletingFiles: numberErrorsDeletingFiles + numberAdditionalErrors)
            }
        }
    }
}
