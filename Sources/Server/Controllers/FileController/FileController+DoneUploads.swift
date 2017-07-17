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
    private func doInitialDoneUploads(params:RequestProcessingParameters) -> (numberTransferred:Int32, uploadDeletions:[FileInfo]?)? {
        
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
        
        // 1) Transfer info to the FileIndex repository from Upload.
        let numberTransferred =
            params.repos.fileIndex.transferUploads(uploadUserId: params.currentSignedInUser!.userId, owningUserId: params.currentSignedInUser!.effectiveOwningUserId,
                deviceUUID: params.deviceUUID!,
                uploadRepo: params.repos.upload)
        
        if numberTransferred == nil  {
            Log.error("Failed on transfer to FileIndex!")
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
            Log.error("Failed to get upload deletions: \(error)")
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
                Log.error("Failed to get fileIndex: \(error)")
                params.completion(nil)
                return nil
            }
        }
        
        // 3) Remove the corresponding records from the Upload repo-- this is specific to the userId and the deviceUUID.
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
        
        return (numberTransferred!, fileIndexDeletions)
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

        guard let (numberTransferred, uploadDeletions) = result else {
            Log.debug("Error in doInitialDoneUploads!")
            // Don't do `params.completion(nil)` because we may not be passing back nil, i.e., for a master version update. The params.completion call was made in doInitialDoneUploads if needed.
            return
        }
        
        // Next: If there are any upload deletions, we need to actually do the file deletions. We are doing this *without* the lock held. I'm assuming it takes far longer to contact the cloud storage service than the other operations we are doing (e.g., mySQL operations).
        
        guard let googleCreds = params.effectiveOwningUserCreds as? GoogleCreds else {
            Log.error("Could not obtain Google Creds")
            params.completion(nil)
            return
        }
        
        if uploadDeletions == nil || uploadDeletions!.count == 0 {
            let response = DoneUploadsResponse()!
            response.numberUploadsTransferred = numberTransferred
            Log.debug("doneUploads.numberUploadsTransferred: \(numberTransferred)")
            params.completion(response)
            return
        }
        
        let async = AsyncTailRecursion()
        async.start {
            self.finishDoneUploads(uploadDeletions: uploadDeletions, params: params, googleCreds: googleCreds, numberTransferred: numberTransferred, async:async)
        }
    }

     private func finishDoneUploads(uploadDeletions:[FileInfo]?, params:RequestProcessingParameters, googleCreds:GoogleCreds, numberTransferred:Int32, async:AsyncTailRecursion, numberErrorsDeletingFiles:Int32 = 0) {
    
        // Base case.
        if uploadDeletions == nil || uploadDeletions!.count == 0 {
            let response = DoneUploadsResponse()!
            
            if numberErrorsDeletingFiles > 0 {
                response.numberDeletionErrors = numberErrorsDeletingFiles
                Log.debug("doneUploads.numberDeletionErrors: \(numberErrorsDeletingFiles)")
            }
            
            response.numberUploadsTransferred = numberTransferred
            Log.debug("doneUploads.numberUploadsTransferred: \(numberTransferred)")
            params.completion(response)
            async.done()
            return
        }
        
        // Recursive case.
        let uploadDeletion = uploadDeletions![0]
        let cloudFileName = uploadDeletion.cloudFileName(deviceUUID: uploadDeletion.deviceUUID!)

        Log.info("Deleting file: \(cloudFileName)")
        
        googleCreds.deleteFile(cloudFolderName: uploadDeletion.cloudFolderName!, cloudFileName: cloudFileName, mimeType: uploadDeletion.mimeType!) { error in

            let tail = (uploadDeletions!.count > 0) ?
                Array(uploadDeletions![1..<uploadDeletions!.count]) : nil
            var numberAdditionalErrors:Int32 = 0
            
            if error != nil {
                // We could get into some odd situations here if we actually report an error by failing. Failing will cause a db transaction rollback. Which could mean we had some files deleted, but *all* of the entries would still be present in the FileIndex/Uploads directory. So, I'm not going to fail, but forge on. I'll report the errors in the DoneUploadsResponse message though.
                // TODO: *1* A better way to deal with this situation could be to use transactions at a finer grained level. Each deletion we do from Upload and FileIndex for an UploadDeletion could be in a transaction that we don't commit until the deletion succeeds with cloud storage.
                Log.warning("Error occurred while deleting Google file: \(error!)")
                numberAdditionalErrors = 1
            }
            
            async.next() {
                self.finishDoneUploads(uploadDeletions: tail, params: params, googleCreds: googleCreds, numberTransferred: numberTransferred, async:async, numberErrorsDeletingFiles: numberErrorsDeletingFiles + numberAdditionalErrors)
            }
        }
    }
}
