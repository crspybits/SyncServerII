//
//  FinishUploads.swift
//  Server
//
//  Created by Christopher G Prince on 7/5/20.
//

// This is the replacement for DoneUploads. It's not invoked from an endpoint, but rather from UploadFile.

import Foundation
import ServerShared
import LoggerAPI

protocol FinishUploadsParameters {
    var repos: Repositories! {get set}
    
    // This must be non-nil
    var currentSignedInUser: User? {get}
}

class FinishUploadFiles {
    private let sharingGroupUUID: String
    private let deviceUUID: String
    private var params:FinishUploadsParameters
    private let currentSignedInUser: UserId
    private let uploader: UploaderProtocol
    
    /** This is for both file uploads, and upload deletions.
     * Specific upload use cases:
     * 1) v0 file uploads
     *  a) A v0 file upload that is 1 out of 1
     *  b) A v0 file upload that is N out of M, M > 1, N < M.
     *  c) A v0 file upload that is N out of M, M > 1, N == M.
     *      In all of these *only* v0 uploads can be present.
     * 2) vN file uploads, N > 0.
     *  a) A vN file upload that is 1 out of 1
     *  b) A vN file upload that is N out of M, M > 1, N < M.
     *  c) A vN file upload that is N out of M, M > 1, N == M.
     *      In all of these *only* vN uploads can be present.
     *
     * Errors:
     *  a) More than one file in batch, but both have nil fileGroupUUID.
     *  b) More than one file in batch, but they have different fileGroupUUID's.
     */
    
    init?(sharingGroupUUID: String, deviceUUID: String, uploader: UploaderProtocol, params:FinishUploadsParameters) {
        self.sharingGroupUUID = sharingGroupUUID
        self.deviceUUID = deviceUUID
        self.params = params
        self.uploader = uploader
        
        // Get uploads for the current signed in user -- uploads are identified by userId, not effectiveOwningUserId, because we want to organize uploads by specific user.
        guard let currentSignedInUser = params.currentSignedInUser?.userId else {
            let message = "Could not get userId"
            Log.error(message)
            return nil
        }
        
        self.currentSignedInUser = currentSignedInUser
    }
    
    enum UploadsResponse {
        // Given the uploadIndex's and uploadCount's in the Upload table, it's not yet time to do a FinishUploads.
        case allUploadsNotYetReceived
        
        case success
        
        case deferred(deferredUploadId: Int64, runner: RequestHandler.PostRequestRunner)
        
        case error(message: String?)
    }
    
    // For v0 uploads, tranfers the Upload records to FileIndex
    // For vN uploads, creates DeferredUpload records.
    func finish() throws -> UploadsResponse {
        let currentUploads: [Upload]
        
        // deferredUploadIdNull true because once these rows have a non-null  deferredUploadId they are pending deferred transfer and we should not deal with them here.
        let fileUploadsResult = params.repos.upload.uploadedFiles(forUserId: currentSignedInUser, sharingGroupUUID: sharingGroupUUID, deviceUUID: deviceUUID, deferredUploadIdNull: true)
        
        switch fileUploadsResult {
        case .uploads(let uploads):
            currentUploads = uploads
        case .error(let error):
            let message = "Failed to get file uploads: \(String(describing: error))"
            Log.error(message)
            return .error(message: message)
        }
        
        guard currentUploads.count > 0 else {
            // This is an internal error. Why would we be calling finishUploads if there wan't at least one upload?
            let message = "Not at least one upload"
            Log.error(message)
            return .error(message: message)
        }
        
        // All uploads must have the same fileGroupUUID.
        let fileGroupUUID = currentUploads[0].fileGroupUUID
        guard currentUploads.filter({$0.fileGroupUUID == fileGroupUUID}).count == currentUploads.count else {
            let message = "All uploads don't have the same fileGroupUUID"
            Log.error(message)
            return .error(message: message)
        }
        
        // If there is more than one file, must have a fileGroupUUID. Thus, only with just a single file can it have a nil fileGroupUUID.
        if fileGroupUUID == nil && currentUploads.count > 1 {
            let message = "More than one upload and they have nil fileGroupUUID"
            Log.error(message)
            return .error(message: message)
        }
        
        guard let uploadCount = currentUploads[0].uploadCount else {
            let message = "No uploadCount"
            Log.error(message)
            return .error(message: message)
        }
        
        guard currentUploads.filter({$0.uploadCount != uploadCount}).count == 0 else {
            let message = "Mismatch: At least one of the uploads had an uploadCount different than: \(uploadCount)"
            Log.error(message)
            return .error(message: message)
        }
        
        let actualIndexes = Set<Int32>(currentUploads.compactMap({$0.uploadIndex}))
        let expectedIndexes = Set<Int32>(1...uploadCount)
        guard actualIndexes == expectedIndexes else {
            Log.info("Expected indexes: \(expectedIndexes), actual indexes: \(actualIndexes); number of current uploads: \(currentUploads.count)")
            return .allUploadsNotYetReceived
        }
        
        // All of the uploads must have an upload state
        guard currentUploads.filter({$0.state == nil}).count == 0 else {
            let message = "Some of the upload states were nil"
            Log.error(message)
            return .error(message: message)
        }
        
        // All uploads must be the same (either v0 or vN, N > 1)
        guard currentUploads.filter({$0.state.isUploadFile &&
            $0.state == currentUploads[0].state}).count == currentUploads.count else {
            let message = "All uploads must be either v0 or vN, N > 1"
            Log.error(message)
            return .error(message: message)
        }
        
        let vNUploads = currentUploads.filter({$0.state == .vNUploadFileChange}).count > 0
        
        if vNUploads {
            // Mark the uploads to indicate they are ready for deferred transfer.
            guard let deferredUploadId = markUploadsAsDeferred(signedInUserId: currentSignedInUser, fileGroupUUID: fileGroupUUID, uploads: currentUploads) else {
                let message = "Failed markUploadsAsDeferred"
                Log.error(message)
                return .error(message: message)
            }
            
            // Doing uploader.run post-request as this will be after the database commit has occurred for the commit-- and we'll be able to fetch DeferredUpload's from the database then.
            // I'm specifically capturing a strong reference to `self` in the following closure. I want the enum associated value to keep self until the `run` is finished its (synchronous) processing.
            return .deferred(deferredUploadId: deferredUploadId, runner: { try self.uploader.run() })
        }
        
        // Else: v0 uploads-- files have already been uploaded. Just need to do the transfer to the FileIndex.
        return transfer(currentUploads: currentUploads)
    }
    
    // For v0 uploads only.
    private func transfer(currentUploads: [Upload]) -> UploadsResponse {
       // Deferring computation of `effectiveOwningUserId` because: (a) don't always need it in the `transferUploads` below, and (b) it will cause unecessary failures in some cases where a sharing owner user has been removed. effectiveOwningUserId is only needed when v0 of a file is being uploaded.
        var effectiveOwningUserId: UserId?
        func getEffectiveOwningUserId() -> FileIndexRepository.EffectiveOwningUser {
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
        
        // Transfer info to the FileIndex repository from Upload.
        let numberTransferredResult =
            params.repos.fileIndex.transferUploads(uploadUserId: params.currentSignedInUser!.userId, owningUserId: getEffectiveOwningUserId, sharingGroupUUID: sharingGroupUUID,
                uploadingDeviceUUID: deviceUUID,
                uploadRepo: params.repos.upload)
        
        var numberTransferred: Int32!
        switch numberTransferredResult {
        case .success(numberUploadsTransferred: let num):
            numberTransferred = num
        case .failure(let failureResult):
            let message = "Failed on transfer to FileIndex: \(String(describing: failureResult))"
            Log.error(message)
            return .error(message: message)
        }
        
        // Remove the corresponding records from the Upload repo-- this is specific to the userId and the deviceUUID.
        let filesForUserDevice = UploadRepository.LookupKey.filesForUserDevice(userId: params.currentSignedInUser!.userId, deviceUUID: deviceUUID, sharingGroupUUID: sharingGroupUUID)
        
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
                return .error(message: message)
            }
        
        default:
            let message = "Failed removing rows from Upload: \(removalResult)"
            Log.error(message)
            return .error(message: message)
        }
        
        return .success
    }
    
    // This is called only for vN files. These files will already be in the FileIndex.
    private func markUploadsAsDeferred(signedInUserId: UserId, fileGroupUUID: String?, uploads: [Upload]) -> Int64? {
        let deferredUpload = DeferredUpload()
        deferredUpload.status = .pendingChange
        deferredUpload.sharingGroupUUID = sharingGroupUUID
        deferredUpload.fileGroupUUID = fileGroupUUID
        deferredUpload.userId = signedInUserId
        
        let result = params.repos.deferredUpload.retry {[unowned self] in
            return self.params.repos.deferredUpload.add(deferredUpload)
        }
        
        let deferredUploadId: Int64
        
        switch result {
        case .success(deferredUploadId: let id):
            deferredUploadId = id
        
        default:
            Log.error("Failed inserting DeferredUpload: \(result)")
            return nil
        }
        
        for upload in uploads {
            upload.deferredUploadId = deferredUploadId
            guard params.repos.upload.update(upload: upload, fileInFileIndex: true) else {
                return nil
            }
        }
        
        return deferredUploadId
    }
}

extension FinishUploadFiles {
    // Returns nil on an error.
    private func getIndexEntries(forUploadFiles uploadFiles:[Upload], fileIndex:FileIndexRepository) -> [FileInfo]? {
        var primaryFileIndexKeys = [FileIndexRepository.LookupKey]()
    
        for uploadFile in uploadFiles {
            // 12/1/17; Up until today, I was using the params.currentSignedInUser!.userId in here and not the effective user id. Thus, when sharing users did an upload deletion, the files got deleted from the file index, but didn't get deleted from cloud storage.
            // 6/24/18; Now things have changed again: With the change to having multiple owning users in a sharing group, a sharingGroup id is the key instead of the userId.
            primaryFileIndexKeys += [.primaryKeys(sharingGroupUUID: uploadFile.sharingGroupUUID, fileUUID: uploadFile.fileUUID)]
        }
    
        var fileIndexObjs = [FileInfo]()
    
        if primaryFileIndexKeys.count > 0 {
            let fileIndexResult = fileIndex.fileIndex(forKeys: primaryFileIndexKeys)
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
