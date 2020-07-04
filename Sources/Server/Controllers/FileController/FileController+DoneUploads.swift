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
import ServerShared
import ServerAccount

extension FileController {
    enum EffectiveOwningUser {
        case success(UserId)
        case failure(RequestHandler.FailureResult)
    }
    
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
            let message = "Failed to get file uploads: \(String(describing: error))"
            Log.error(message)
            return .doCompletion(.failure(.message(message)))
        }

        // Now, map the upload objects found to the file index. What we need here are not just the entries from the `Upload` table-- we need the corresponding entries from FileIndex since those have the deviceUUID's that we need in order to correctly name the files in cloud storage.
        
        guard let staleVersionsToDelete = getIndexEntries(forUploadFiles: staleVersionsFromUploads, params:params) else {
            let message = "Failed to getIndexEntries for staleVersionsFromUploads: \(String(describing: staleVersionsFromUploads))"
            Log.error(message)
            return .doCompletion(.failure(.message(message)))
        }
        
        guard let fileIndexDeletions = getIndexEntries(forUploadFiles: uploadDeletions, params:params) else {
            let message = "Failed to getIndexEntries for uploadDeletions: \(String(describing: uploadDeletions))"
            Log.error(message)
            return .doCompletion(.failure(.message(message)))
        }

        // Deferring computation of `effectiveOwningUserId` because: (a) don't always need it in the `transferUploads` below, and (b) it will cause unecessary failures in some cases where a sharing owner user has been removed. effectiveOwningUserId is only needed when v0 of a file is being uploaded.
        var effectiveOwningUserId: UserId?
        func getEffectiveOwningUserId() -> EffectiveOwningUser {
            if let effectiveOwningUserId = effectiveOwningUserId {
                return .success(effectiveOwningUserId)
            }
            
            let geouiResult = Controllers.getEffectiveOwningUserId(user: params.currentSignedInUser!, sharingGroupUUID: doneUploadsRequest.sharingGroupUUID, sharingGroupUserRepo: params.repos.sharingGroupUser)
            switch geouiResult {
            case .found(let userId):
                effectiveOwningUserId = userId
                return .success(userId)
            case .noObjectFound, .gone:
                let message = "No effectiveOwningUserId: \(geouiResult)"
                Log.debug(message)
                return .failure(.goneWithReason(message: message, .userRemoved))
            case .error:
                let message = "Failed to getEffectiveOwningUserId"
                Log.error(message)
                return .failure(.message(message))
            }
        }
        
        // 3) Transfer info to the FileIndex repository from Upload.
        let numberTransferredResult =
            params.repos.fileIndex.transferUploads(uploadUserId: params.currentSignedInUser!.userId, owningUserId: getEffectiveOwningUserId, sharingGroupUUID: doneUploadsRequest.sharingGroupUUID,
                uploadingDeviceUUID: params.deviceUUID!,
                uploadRepo: params.repos.upload)
        
        var numberTransferred: Int32!
        switch numberTransferredResult {
        case .success(numberUploadsTransferred: let num):
            numberTransferred = num
        case .failure(let failureResult):
            let message = "Failed on transfer to FileIndex!"
            Log.error(message)
            return .doCompletion(.failure(failureResult))
        }
        
        // 4) Remove the corresponding records from the Upload repo-- this is specific to the userId and the deviceUUID.
        let filesForUserDevice = UploadRepository.LookupKey.filesForUserDevice(userId: params.currentSignedInUser!.userId, deviceUUID: params.deviceUUID!, sharingGroupUUID: doneUploadsRequest.sharingGroupUUID)
        
        // 5/28/17; I just got an error on this: 
        // [ERR] Number rows removed from Upload was 10 but should have been Optional(9)!
        // How could this happen?
        // 9/23/18; It could have been a race condition across test cases with the same device UUID and user. I'm now adding in a sharing group UUID qualifier, so I wonder if this will solve that problem too?
        
        let removalResult = params.repos.upload.retry {
            return params.repos.upload.remove(key: filesForUserDevice)
        }
        
        switch removalResult {
        case .removed(let numberRows):
            if numberRows != numberTransferred {
                let message = "Number rows removed from Upload was \(numberRows) but should have been \(String(describing: numberTransferred))!"
                Log.error(message)
                return .doCompletion(.failure(.message(message)))
            }
        
        case .deadlock:
            let message = "Failed removing rows from Upload: deadlock!"
            Log.error(message)
            return .doCompletion(.failure(.message(message)))
        
        case .waitTimeout:
            let message = "Failed removing rows from Upload: wait timeout!"
            Log.error(message)
            return .doCompletion(.failure(.message(message)))
            
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
        
        let result = doInitialDoneUploads(params: params, doneUploadsRequest: doneUploadsRequest)

        guard case .success(let numberTransferred, let uploadDeletions, let staleVersionsToDelete) = result else {
            Log.debug("Success on doInitialDoneUploads: \(result)")
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
            func successResponse() {
                let response = DoneUploadsResponse()
                response.numberUploadsTransferred = numberTransferred
                Log.debug("no upload deletions or stale file versions: doneUploads.numberUploadsTransferred: \(numberTransferred)")
                params.completion(.success(response))
            }
            
            if let pushNotificationMessage = doneUploadsRequest.pushNotificationMessage {
                sendNotifications(fromUser: params.currentSignedInUser!, forSharingGroupUUID: doneUploadsRequest.sharingGroupUUID, message: pushNotificationMessage, params: params) { success in
                    if success {
                        successResponse()
                    }
                    else {
                        let message = "Failed on sendNotifications with no cloud deletions."
                        Log.debug(message)
                        params.completion(.failure(.message(message)))
                    }
                }
            }
            else {
                successResponse()
            }
            
            return
        }
        
        // Do deletions
        let async = AsyncTailRecursion()
        async.start {
            self.finishDoneUploads(cloudDeletions: cloudDeletions, params: params, numberTransferred: Int(numberTransferred), pushNotificationMessage: doneUploadsRequest.pushNotificationMessage, sharingGroupUUID: doneUploadsRequest.sharingGroupUUID, async:async)
        }
    }

     private func finishDoneUploads(cloudDeletions:[FileInfo], params:RequestProcessingParameters, numberTransferred: Int, pushNotificationMessage: String?, sharingGroupUUID: String, async:AsyncTailRecursion, numberErrorsDeletingFiles:Int32 = 0) {
    
        // Base case.
        if cloudDeletions.count == 0 {
            func successResponse() {
                let response = DoneUploadsResponse()
            
                if numberErrorsDeletingFiles > 0 {
                    response.numberDeletionErrors = numberErrorsDeletingFiles
                    Log.debug("doneUploads.numberDeletionErrors: \(numberErrorsDeletingFiles)")
                }
            
                response.numberUploadsTransferred = Int32(numberTransferred)
                Log.debug("base case: doneUploads.numberUploadsTransferred: \(numberTransferred)")
                params.completion(.success(response))
            }
            
            if pushNotificationMessage == nil {
                successResponse()
                async.done()
            }
            else {
                sendNotifications(fromUser: params.currentSignedInUser!, forSharingGroupUUID: sharingGroupUUID, message: pushNotificationMessage!, params: params) { success in
                    if success {
                        successResponse()
                    }
                    else {
                        let message = "Failed on sendNotifications in finishDoneUploads"
                        Log.error(message)
                        params.completion(.failure(.message(message)))
                    }
                    
                    async.done()
                }
            }

            return
        }
        
        // Recursive case.
        let cloudDeletion = cloudDeletions[0]
        
        // DEPRECATED
        var cloudFileName: String! //  = cloudDeletion.cloudFileName(deviceUUID: cloudDeletion.deviceUUID!, mimeType: cloudDeletion.mimeType!)

        Log.info("Deleting file: \(String(describing: cloudFileName))")
        
        // OWNER
        guard let owningUserCreds = FileController.getCreds(forUserId: cloudDeletion.owningUserId, from: params.db, accountManager: params.accountManager) else {
            let message = "Could not obtain owning users creds"
            Log.error(message)
            params.completion(.failure(.message(message)))
            return
        }
    
        guard let cloudStorageCreds = owningUserCreds.cloudStorage else {
            let message = "Could not obtain cloud storage creds."
            Log.error(message)
            params.completion(.failure(.message(message)))
            return
        }
        
        let options = CloudStorageFileNameOptions(cloudFolderName: owningUserCreds.cloudFolderName, mimeType: cloudDeletion.mimeType!)
        
        cloudStorageCreds.deleteFile(cloudFileName: cloudFileName, options: options) { result in

            let tail = (cloudDeletions.count > 0) ?
                Array(cloudDeletions[1..<cloudDeletions.count]) : []
            var numberAdditionalErrors:Int32 = 0
            
            switch result {
            case .success:
                break
            case .accessTokenRevokedOrExpired:
                // Handling this the same way as [1] below.
                Log.warning("Error occurred while deleting file: Access token revoked or expired")
                numberAdditionalErrors = 1
                
            case .failure(let error):
                // [1]. We could get into some odd situations here if we actually report an error by failing. Failing will cause a db transaction rollback. Which could mean we had some files deleted, but *all* of the entries would still be present in the FileIndex/Uploads directory. So, I'm not going to fail, but forge on. I'll report the errors in the DoneUploadsResponse message though.
                // TODO: *1* A better way to deal with this situation could be to use transactions at a finer grained level. Each deletion we do from Upload and FileIndex for an UploadDeletion could be in a transaction that we don't commit until the deletion succeeds with cloud storage.
                Log.warning("Error occurred while deleting file: \(error)")
                numberAdditionalErrors = 1
            }
            
            async.next() {
                self.finishDoneUploads(cloudDeletions: tail, params: params, numberTransferred: numberTransferred, pushNotificationMessage: pushNotificationMessage, sharingGroupUUID: sharingGroupUUID, async:async, numberErrorsDeletingFiles: numberErrorsDeletingFiles + numberAdditionalErrors)
            }
        }
    }
    
    // Returns true iff success.
    private func sendNotifications(fromUser: User, forSharingGroupUUID sharingGroupUUID: String, message: String, params:RequestProcessingParameters, completion: @escaping (_ success: Bool)->()) {

        guard var users:[User] = params.repos.sharingGroupUser.sharingGroupUsers(forSharingGroupUUID: sharingGroupUUID) else {
            Log.error(("sendNotifications: Failed to get sharing group users!"))
            completion(false)
            return
        }
        
        // Remove sending user from users. They already know they uploaded/deleted-- no point in sending them a notification.
        // Also remove any users that don't have topics-- i.e., they don't have any devices registered for push notifications.
        users = users.filter { user in
            user.userId != fromUser.userId && user.pushNotificationTopic != nil
        }
        
        let key = SharingGroupRepository.LookupKey.sharingGroupUUID(sharingGroupUUID)
        let sharingGroupResult = params.repos.sharingGroup.lookup(key: key, modelInit: SharingGroup.init)
        var sharingGroup: SharingGroup!
        
        switch sharingGroupResult {
        case .found(let model):
            sharingGroup = (model as! SharingGroup)
        case .error(let error):
            Log.error("sendNotifications: \(error)")
            completion(false)
            return
        case .noObjectFound:
            Log.error("sendNotifications: No object found!")
            completion(false)
            return
        }
        
        var modifiedMessage = "\(fromUser.username!)"
        
        if let name = sharingGroup.sharingGroupName {
            modifiedMessage += ", \(name)"
        }
        
        modifiedMessage += ": " + message
        
        guard let formattedMessage = PushNotifications.format(message: modifiedMessage) else {
            Log.error("sendNotifications: Failed on formatting message.")
            completion(false)
            return
        }
        
        guard let pn = PushNotifications() else {
            Log.error("sendNotifications: Failed on PushNotifications constructor.")
            completion(false)
            return
        }
        
        pn.send(formattedMessage: formattedMessage, toUsers: users, completion: completion)
    }
}
