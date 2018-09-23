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
    private func getIndexEntries(forUploadFiles uploadFiles:[Upload], params:RequestProcessingParameters) -> [FileInfo]? {
        var primaryFileIndexKeys = [FileIndexRepository.LookupKey]()
    
        for uploadFile in uploadFiles {
            // 12/1/17; Up until today, I was using the params.currentSignedInUser!.userId in here and not the effective user id. Thus, when sharing users did an upload deletion, the files got deleted from the file index, but didn't get deleted from cloud storage.
            // 6/24/18; Now things have changed again: With the change to having multiple owning users in a sharing group, a sharingGroup id is the key instead of the userId.
            primaryFileIndexKeys += [.primaryKeys(sharingGroupUUID: uploadFile.sharingGroupUUID, fileUUID: uploadFile.fileUUID)]
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
    
    enum DoInitialDoneUploadResponse {
        case success(numberTransferred:Int32, uploadDeletions:[FileInfo]?, staleVersionsToDelete:[FileInfo]?)
        case doCompletion(RequestProcessingParameters.Response)
    }
    
    // staleVersionsToDelete gives info, if any, on files that we're uploading new versions of.
    private func doInitialDoneUploads(params:RequestProcessingParameters, doneUploadsRequest: DoneUploadsRequest) -> DoInitialDoneUploadResponse {
        
#if DEBUG
        if doneUploadsRequest.testLockSync != nil {
            Log.info("Starting sleep (testLockSync= \(String(describing: doneUploadsRequest.testLockSync))).")
            Thread.sleep(forTimeInterval: TimeInterval(doneUploadsRequest.testLockSync!))
            Log.info("Finished sleep (testLockSync= \(String(describing: doneUploadsRequest.testLockSync))).")
        }
#endif
        
        if let response = Controllers.updateMasterVersion(sharingGroupUUID: doneUploadsRequest.sharingGroupUUID, masterVersion: doneUploadsRequest.masterVersion, params: params, responseType: DoneUploadsResponse.self) {
            return .doCompletion(response)
        }
        
        // Now, start the heavy lifting. This has to accomodate both file uploads, and upload deletions-- because these both need to alter the masterVersion (i.e., they change the file index).
        
        // 1) See if any of the file uploads are for file versions > 0. Later, we'll have to delete stale versions of the file(s) in cloud storage if so.
        // 2) Get the upload deletions, if any.
        
        var staleVersionsFromUploads:[Upload]
        var uploadDeletions:[Upload]
        
        // Get uploads for the current signed in user -- uploads are identified by userId, not effectiveOwningUserId, because we want to organize uploads by specific user.
        let fileUploadsResult = params.repos.upload.uploadedFiles(forUserId: params.currentSignedInUser!.userId, sharingGroupUUID: doneUploadsRequest.sharingGroupUUID, deviceUUID: params.deviceUUID!)
        switch fileUploadsResult {
        case .uploads(let uploads):
            Log.debug("Number of file uploads and upload deletions: \(uploads.count)")
            // 1) Filter out uploaded files with versions > 0 -- for the stale file versions. Note that we're not including files with status `uploadedUndelete`-- we don't need to delete any stale versions for these.
            staleVersionsFromUploads = uploads.filter({
                // The left to right order of these checks is important-- check the state first. If the state is uploadingAppMetaData, there will be a nil fileVersion and don't want to check that.
                $0.state == .uploadedFile && $0.fileVersion > 0
            })
            
            // 2) Filter out upload deletions
            uploadDeletions = uploads.filter({$0.state == .toDeleteFromFileIndex})

        case .error(let error):
            let message = "Failed to get file uploads: \(error)"
            Log.error(message)
            return .doCompletion(.failure(.message(message)))
        }

        // Now, map the upload objects found to the file index. What we need here are not just the entries from the `Upload` table-- we need the corresponding entries from FileIndex since those have the deviceUUID's that we need in order to correctly name the files in cloud storage.
        
        guard let staleVersionsToDelete = getIndexEntries(forUploadFiles: staleVersionsFromUploads, params:params) else {
            return .doCompletion(.failure(nil))
        }
        
        guard let fileIndexDeletions = getIndexEntries(forUploadFiles: uploadDeletions, params:params) else {
            return .doCompletion(.failure(nil))
        }

        guard let effectiveOwningUserId = Controllers.getEffectiveOwningUserId(user: params.currentSignedInUser!, sharingGroupUUID: doneUploadsRequest.sharingGroupUUID, sharingGroupUserRepo: params.repos.sharingGroupUser) else {
            return .doCompletion(.failure(nil))
        }
        
        // 3) Transfer info to the FileIndex repository from Upload.
        let numberTransferred =
            params.repos.fileIndex.transferUploads(uploadUserId: params.currentSignedInUser!.userId, owningUserId: effectiveOwningUserId, sharingGroupUUID: doneUploadsRequest.sharingGroupUUID,
                uploadingDeviceUUID: params.deviceUUID!,
                uploadRepo: params.repos.upload)
        
        if numberTransferred == nil  {
            let message = "Failed on transfer to FileIndex!"
            Log.error(message)
            return .doCompletion(.failure(.message(message)))
        }
        
        // 4) Remove the corresponding records from the Upload repo-- this is specific to the userId and the deviceUUID.
        let filesForUserDevice = UploadRepository.LookupKey.filesForUserDevice(userId: params.currentSignedInUser!.userId, deviceUUID: params.deviceUUID!, sharingGroupUUID: doneUploadsRequest.sharingGroupUUID)
        
        // 5/28/17; I just got an error on this: 
        // [ERR] Number rows removed from Upload was 10 but should have been Optional(9)!
        // How could this happen?
        // 9/23/18; It could have been a race condition across test cases with the same device UUID and user. I'm now adding in a sharing group UUID qualifier, so I wonder if this will solve that problem too?
        
        switch params.repos.upload.remove(key: filesForUserDevice) {
        case .removed(let numberRows):
            if numberRows != numberTransferred {
                let message = "Number rows removed from Upload was \(numberRows) but should have been \(String(describing: numberTransferred))!"
                Log.error(message)
                return .doCompletion(.failure(.message(message)))
            }
            
        case .error(_):
            let message = "Failed removing rows from Upload!"
            Log.error(message)
            return .doCompletion(.failure(.message(message)))
        }
        
        // See if we have to do a sharing group update operation.
        if let sharingGroupName = doneUploadsRequest.sharingGroupName {
            let serverSharingGroup = Server.SharingGroup()
            serverSharingGroup.sharingGroupUUID = doneUploadsRequest.sharingGroupUUID
            serverSharingGroup.sharingGroupName = sharingGroupName

            if !params.repos.sharingGroup.update(sharingGroup: serverSharingGroup) {
                let message = "Failed in updating sharing group."
                Log.error(message)
                return .doCompletion(.failure(.message(message)))
            }
        }
        
        return .success(numberTransferred:numberTransferred!, uploadDeletions:fileIndexDeletions, staleVersionsToDelete:staleVersionsToDelete)
    }
    
    func doneUploads(params:RequestProcessingParameters) {
        guard let doneUploadsRequest = params.request as? DoneUploadsRequest else {
            let message = "Did not receive DoneUploadsRequest"
            Log.error(message)
            params.completion(.failure(.message(message)))
            return
        }
        
        guard sharingGroupSecurityCheck(sharingGroupUUID: doneUploadsRequest.sharingGroupUUID, params: params) else {
            let message = "Failed in sharing group security check."
            Log.error(message)
            params.completion(.failure(.message(message)))
            return
        }
        
        let lock = Lock(sharingGroupUUID:doneUploadsRequest.sharingGroupUUID, deviceUUID:params.deviceUUID!)
        switch params.repos.lock.lock(lock: lock) {
        case .success:
            break
        
        case .lockAlreadyHeld:
            let message = "Error: Lock already held!"
            Log.debug(message)
            params.completion(.failure(.message(message)))
            return
        
        case .errorRemovingStaleLocks, .modelValueWasNil, .otherError:
            let message = "Error removing locks!"
            Log.debug(message)
            params.completion(.failure(.message(message)))
            return
        }
        
        let result = doInitialDoneUploads(params: params, doneUploadsRequest: doneUploadsRequest)
        
        if !params.repos.lock.unlock(sharingGroupUUID: doneUploadsRequest.sharingGroupUUID) {
            let message = "Error in unlock!"
            Log.debug(message)
            
            // So in the case of multiple errors, don't get a completion in the unlock AND a completion in doInitialDoneUploads.
            switch result {
            case .doCompletion(let response):
                params.completion(response)
            case .success:
                params.completion(.failure(.message(message)))
            }
            return
        }

        guard case .success(let numberTransferred, let uploadDeletions, let staleVersionsToDelete) = result else {
            Log.error("Error in doInitialDoneUploads!")
            switch result {
            case .doCompletion(let response):
                params.completion(response)
            case .success:
                assert(false)
            }
            return
        }
        
        // Next: If there are any upload deletions, we need to actually do the file deletions. We are doing this *without* the lock held. I'm assuming it takes far longer to contact the cloud storage service than the other operations we are doing (e.g., mySQL operations).
        
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
            params.completion(.success(response))
            return
        }
        
        let async = AsyncTailRecursion()
        async.start {
            self.finishDoneUploads(cloudDeletions: cloudDeletions, params: params, numberTransferred: numberTransferred, async:async)
        }
    }

     private func finishDoneUploads(cloudDeletions:[FileInfo], params:RequestProcessingParameters, numberTransferred:Int32, async:AsyncTailRecursion, numberErrorsDeletingFiles:Int32 = 0) {
    
        // Base case.
        if cloudDeletions.count == 0 {
            let response = DoneUploadsResponse()!
            
            if numberErrorsDeletingFiles > 0 {
                response.numberDeletionErrors = numberErrorsDeletingFiles
                Log.debug("doneUploads.numberDeletionErrors: \(numberErrorsDeletingFiles)")
            }
            
            response.numberUploadsTransferred = numberTransferred
            Log.debug("base case: doneUploads.numberUploadsTransferred: \(numberTransferred)")
            params.completion(.success(response))
            async.done()
            return
        }
        
        // Recursive case.
        let cloudDeletion = cloudDeletions[0]
        let cloudFileName = cloudDeletion.cloudFileName(deviceUUID: cloudDeletion.deviceUUID!, mimeType: cloudDeletion.mimeType!)

        Log.info("Deleting file: \(cloudFileName)")
        
        // OWNER
        guard let owningUserCreds = FileController.getCreds(forUserId: cloudDeletion.owningUserId, from: params.db) else {
            let message = "Could not obtain owning users creds"
            Log.error(message)
            params.completion(.failure(.message(message)))
            return
        }
    
        guard let cloudStorageCreds = owningUserCreds as? CloudStorage else {
            let message = "Could not obtain cloud storage creds."
            Log.error(message)
            params.completion(.failure(.message(message)))
            return
        }
        
        let options = CloudStorageFileNameOptions(cloudFolderName: owningUserCreds.cloudFolderName, mimeType: cloudDeletion.mimeType!)
        
        cloudStorageCreds.deleteFile(cloudFileName: cloudFileName, options: options) { error in

            let tail = (cloudDeletions.count > 0) ?
                Array(cloudDeletions[1..<cloudDeletions.count]) : []
            var numberAdditionalErrors:Int32 = 0
            
            if error != nil {
                // We could get into some odd situations here if we actually report an error by failing. Failing will cause a db transaction rollback. Which could mean we had some files deleted, but *all* of the entries would still be present in the FileIndex/Uploads directory. So, I'm not going to fail, but forge on. I'll report the errors in the DoneUploadsResponse message though.
                // TODO: *1* A better way to deal with this situation could be to use transactions at a finer grained level. Each deletion we do from Upload and FileIndex for an UploadDeletion could be in a transaction that we don't commit until the deletion succeeds with cloud storage.
                Log.warning("Error occurred while deleting file: \(error!)")
                numberAdditionalErrors = 1
            }
            
            async.next() {
                self.finishDoneUploads(cloudDeletions: tail, params: params, numberTransferred: numberTransferred, async:async, numberErrorsDeletingFiles: numberErrorsDeletingFiles + numberAdditionalErrors)
            }
        }
    }
}
