//
//  FinishUploads.swift
//  Server
//
//  Created by Christopher G Prince on 7/5/20.
//

// This is the replacement for DoneUploads. It's not invoked from an endpoint, but rather from UploadFile and UploadDeletetion.

import Foundation
import ServerShared
import LoggerAPI

class FinishUploads {
    private let sharingGroupUUID: String
    private let deviceUUID: String
    private let params:RequestProcessingParameters
    private let userId: UserId
    private let sharingGroupName: String?
    
    /** This is for both file uploads, and upload deletions.
     * Specific Use cases:
     * 1) v0 file uploads
     *  a) A v0 file upload that is 1 out of 1
     *  b) A v0 file upload that is N out of M, M > 1, N < M.
     *  c) A v0 file upload that is N out of M, M > 1, N == M.
     *      All of these test to make sure that *only* v0 uploads are present.
     * 2) vN file uploads, N > 0.
     *
     * Errors:
     *  a) More than one file in batch, but both have nil fileGroupUUID.
     *  b) More than one file in batch, but they have different fileGroupUUID's.
     */
    init?(sharingGroupUUID: String, deviceUUID: String, sharingGroupName: String?, params:RequestProcessingParameters) {
        self.sharingGroupUUID = sharingGroupUUID
        self.deviceUUID = deviceUUID
        self.params = params
        self.sharingGroupName = sharingGroupName
        
        // Get uploads for the current signed in user -- uploads are identified by userId, not effectiveOwningUserId, because we want to organize uploads by specific user.
        guard let userId = params.currentSignedInUser?.userId else {
            let message = "Could not get userId"
            Log.error(message)
            return nil
        }
        
        self.userId = userId
    }
    
    enum TransferResponse {
        // Given the uploadIndex's and uploadCount's in the Upload table, it's not yet time to do a FinishUploads.
        case allUploadsNotYetReceived
        
        // TODO: v0 transfer
        case success(numberTransferred:Int32, uploadDeletions:[FileInfo]?, staleVersionsToDelete:[FileInfo]?)
        
        case deferredTransfer
        
        case error(RequestProcessingParameters.Response)
    }

    func transfer() -> TransferResponse {
        let currentUploads: [Upload]
        
        // deferredUploadIdNull true because once these rows have a non-null  deferredUploadId they are pending deferred transfer and we should not deal with them here.
        let fileUploadsResult = params.repos.upload.uploadedFiles(forUserId: userId, sharingGroupUUID: sharingGroupUUID, deviceUUID: deviceUUID, deferredUploadIdNull: true)
        
        switch fileUploadsResult {
        case .uploads(let uploads):
            currentUploads = uploads
        case .error(let error):
            let message = "Failed to get file uploads: \(String(describing: error))"
            Log.error(message)
            return .error(.failure(.message(message)))
        }
        
        guard currentUploads.count > 0 else {
            // This is an internal error. Why would we be calling finishUploads if there wan't at least one upload?
            let message = "Not at least one upload"
            Log.error(message)
            return .error(.failure(.message(message)))
        }
        
        // All uploads must have the same fileGroupUUID.
        let fileGroupUUID = currentUploads[0].fileGroupUUID
        guard currentUploads.filter({$0.fileGroupUUID == fileGroupUUID}).count == currentUploads.count else {
            let message = "All uploads don't have the same fileGroupUUID"
            Log.error(message)
            return .error(.failure(.message(message)))
        }
        
        // If there is more than one file, must have a fileGroupUUID
        if fileGroupUUID == nil && currentUploads.count > 1 {
            let message = "More than one upload and they have nil fileGroupUUID"
            Log.error(message)
            return .error(.failure(.message(message)))
        }
        
        guard let uploadCount = currentUploads[0].uploadCount else {
            let message = "No uploadCount"
            Log.error(message)
            return .error(.failure(.message(message)))
        }
        
        guard currentUploads.filter({$0.uploadCount != uploadCount}).count == 0 else {
            let message = "Mismatch: At least one of the uploads had an uploadCount different than: \(uploadCount)"
            Log.error(message)
            return .error(.failure(.message(message)))
        }
        
        let actualIndexes = Set<Int32>(currentUploads.compactMap({$0.uploadIndex}))
        let expectedIndexes = Set<Int32>(1...uploadCount)
        guard actualIndexes == expectedIndexes else {
            Log.info("Expected indexes: \(expectedIndexes), actual indexes: \(actualIndexes)")
            return .allUploadsNotYetReceived
        }
        
        // All of the uploads must have v0UploadFileVersion non-nil
        guard currentUploads.filter({$0.v0UploadFileVersion == nil}).count == 0 else {
            let message = "Some of the v0UploadFileVersion's were nil"
            Log.error(message)
            return .error(.failure(.message(message)))
        }
        
        // All uploads must be the same (either v0 or vN, N > 1)
        guard currentUploads.filter({$0.v0UploadFileVersion == currentUploads[0].v0UploadFileVersion}).count == currentUploads.count else {
            let message = "All uploads must be either v0 or vN, N > 1"
            Log.error(message)
            return .error(.failure(.message(message)))
        }
        
        let vNUploads = currentUploads.filter({$0.v0UploadFileVersion == false}).count > 0
        
        if vNUploads {
            // Mark the uploads to indicate they are ready for deferred transfer.
            guard markUploadsAsDeferred(uploads: currentUploads) else {
                let message = "Failed markUploadsAsDeferred"
                Log.error(message)
                return .error(.failure(.message(message)))
            }
            
            Uploader.run()
            
            return .deferredTransfer
        }
        
        // Else: v0 uploads-- files have already been uploaded. Just need to do the transfer to the FileIndex.
        return transfer(currentUploads: currentUploads)
    }
    
    private func transfer(currentUploads: [Upload]) -> TransferResponse {
        // 1) See if any of the file uploads are for file versions > 0. Later, we'll have to delete stale versions of the file(s) in cloud storage if so.
        // 2) Get the upload deletions, if any.
        
        Log.debug("Number of file uploads and upload deletions: \(currentUploads.count)")
        
        // 1) Filter out uploaded files with versions > 0 -- for the stale file versions. Note that we're not including files with status `uploadedUndelete`-- we don't need to delete any stale versions for these.
        let staleVersionsFromUploads = currentUploads.filter({
            // The left to right order of these checks is important-- check the state first. If the state is uploadingAppMetaData, there will be a nil fileVersion and don't want to check that.            
            $0.state == .uploadedFile && $0.v0UploadFileVersion == false
        })
        
        // 2) Filter out upload deletions
        let uploadDeletions = currentUploads.filter({$0.state == .toDeleteFromFileIndex})

        // Now, map the upload objects found to the file index. What we need here are not just the entries from the `Upload` table-- we need the corresponding entries from FileIndex since those have the deviceUUID's that we need in order to correctly name the files in cloud storage.
        
        guard let staleVersionsToDelete = getIndexEntries(forUploadFiles: staleVersionsFromUploads, params:params) else {
            let message = "Failed to getIndexEntries for staleVersionsFromUploads: \(String(describing: staleVersionsFromUploads))"
            Log.error(message)
            return .error(.failure(.message(message)))
        }
        
        guard let fileIndexDeletions = getIndexEntries(forUploadFiles: uploadDeletions, params:params) else {
            let message = "Failed to getIndexEntries for uploadDeletions: \(String(describing: uploadDeletions))"
            Log.error(message)
            return .error(.failure(.message(message)))
        }

       // Deferring computation of `effectiveOwningUserId` because: (a) don't always need it in the `transferUploads` below, and (b) it will cause unecessary failures in some cases where a sharing owner user has been removed. effectiveOwningUserId is only needed when v0 of a file is being uploaded.
        var effectiveOwningUserId: UserId?
        func getEffectiveOwningUserId() -> FileController.EffectiveOwningUser {
            if let effectiveOwningUserId = effectiveOwningUserId {
                return .success(effectiveOwningUserId)
            }
            
            let geouiResult = Controllers.getEffectiveOwningUserId(user: params.currentSignedInUser!, sharingGroupUUID: sharingGroupUUID, sharingGroupUserRepo: params.repos.sharingGroupUser)
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
            params.repos.fileIndex.transferUploads(uploadUserId: params.currentSignedInUser!.userId, owningUserId: getEffectiveOwningUserId, sharingGroupUUID: sharingGroupUUID,
                uploadingDeviceUUID: params.deviceUUID!,
                uploadRepo: params.repos.upload)
        
        var numberTransferred: Int32!
        switch numberTransferredResult {
        case .success(numberUploadsTransferred: let num):
            numberTransferred = num
        case .failure(let failureResult):
            let message = "Failed on transfer to FileIndex!"
            Log.error(message)
            return .error(.failure(failureResult))
        }
        
        // 4) Remove the corresponding records from the Upload repo-- this is specific to the userId and the deviceUUID.
        let filesForUserDevice = UploadRepository.LookupKey.filesForUserDevice(userId: params.currentSignedInUser!.userId, deviceUUID: params.deviceUUID!, sharingGroupUUID: sharingGroupUUID)
        
        // 5/28/17; I just got an error on this:
        // [ERR] Number rows removed from Upload was 10 but should have been Optional(9)!
        // How could this happen?
        // 9/23/18; It could have been a race condition across test cases with the same device UUID and user. I'm now adding in a sharing group UUID qualifier, so I wonder if this will solve that problem too?
        
        let removalResult = params.repos.upload.retry {
            return self.params.repos.upload.remove(key: filesForUserDevice)
        }
        
        switch removalResult {
        case .removed(let numberRows):
            if numberRows != numberTransferred {
                let message = "Number rows removed from Upload was \(numberRows) but should have been \(String(describing: numberTransferred))!"
                Log.error(message)
                return .error(.failure(.message(message)))
            }
        
        case .deadlock:
            let message = "Failed removing rows from Upload: deadlock!"
            Log.error(message)
            return .error(.failure(.message(message)))
        
        case .waitTimeout:
            let message = "Failed removing rows from Upload: wait timeout!"
            Log.error(message)
            return .error(.failure(.message(message)))
            
        case .error(_):
            let message = "Failed removing rows from Upload!"
            Log.error(message)
            return .error(.failure(.message(message)))
        }
        
        // See if we have to do a sharing group update operation.
        if let sharingGroupName = sharingGroupName {
            let serverSharingGroup = Server.SharingGroup()
            serverSharingGroup.sharingGroupUUID = sharingGroupUUID
            serverSharingGroup.sharingGroupName = sharingGroupName

            if !params.repos.sharingGroup.update(sharingGroup: serverSharingGroup) {
                let message = "Failed in updating sharing group."
                Log.error(message)
                return .error(.failure(.message(message)))
            }
        }
        
        return .success(numberTransferred:numberTransferred!, uploadDeletions:fileIndexDeletions, staleVersionsToDelete:staleVersionsToDelete)
    }
    
    // This is called only for vN files. These files will already be in the FileIndex.
    private func markUploadsAsDeferred(uploads: [Upload]) -> Bool {
        let deferredUpload = DeferredUpload()
        deferredUpload.status = .pending
        
        let result = params.repos.deferredUpload.retry {[unowned self] in
            return self.params.repos.deferredUpload.add(deferredUpload)
        }
        
        let deferredUploadId: Int64
        
        switch result {
        case .success(deferredUploadId: let id):
            deferredUploadId = id
        
        default:
            Log.error("Failed inserting DeferredUpload: \(result)")
            return false
        }
        
        for upload in uploads {
            upload.deferredUploadId = deferredUploadId
            guard params.repos.upload.update(upload: upload, fileInFileIndex: true) else {
                return false
            }
        }
        
        return true
    }
}

extension FinishUploads {
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
}
