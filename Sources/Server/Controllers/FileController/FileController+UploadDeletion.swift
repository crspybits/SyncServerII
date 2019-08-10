//
//  FileController+UploadDeletion.swift
//  Server
//
//  Created by Christopher Prince on 3/22/17.
//
//

import Foundation
import LoggerAPI
import SyncServerShared
import Kitura

extension FileController {
    func uploadDeletion(params:RequestProcessingParameters) {
        guard let uploadDeletionRequest = params.request as? UploadDeletionRequest else {
            let message = "Did not receive UploadDeletionRequest"
            Log.error(message)
            params.completion(.failure(.message(message)))
            return
        }
        
        guard sharingGroupSecurityCheck(sharingGroupUUID: uploadDeletionRequest.sharingGroupUUID, params: params) else {
            let message = "Failed in sharing group security check."
            Log.error(message)
            params.completion(.failure(.message(message)))
            return
        }
        
        guard uploadDeletionRequest.fileVersion != nil else {
            let message = "File version not given in upload request."
            Log.error(message)
            params.completion(.failure(.message(message)))
            return
        }
        
        Controllers.getMasterVersion(sharingGroupUUID: uploadDeletionRequest.sharingGroupUUID, params: params) { (error, masterVersion) in
            if error != nil {
                let message = "Error: \(String(describing: error))"
                Log.error(message)
                params.completion(.failure(.message(message)))
                return
            }

            if masterVersion != uploadDeletionRequest.masterVersion {
                let response = UploadDeletionResponse()
                Log.warning("Master version update: \(String(describing: masterVersion))")
                response.masterVersionUpdate = masterVersion
                params.completion(.success(response))
                return
            }
            
            // Check whether this fileUUID exists in the FileIndex.

            let key = FileIndexRepository.LookupKey.primaryKeys(sharingGroupUUID: uploadDeletionRequest.sharingGroupUUID, fileUUID: uploadDeletionRequest.fileUUID)
            
            let lookupResult = params.repos.fileIndex.lookup(key: key, modelInit: FileIndex.init)
            
            var fileIndexObj:FileIndex!
            
            switch lookupResult {
            case .found(let modelObj):
                fileIndexObj = modelObj as? FileIndex
                if fileIndexObj == nil {
                    let message = "Could not convert model object to FileIndex"
                    Log.error(message)
                    params.completion(.failure(.message(message)))
                    return
                }
                
            case .noObjectFound:
                let message = "Could not find file to delete in FileIndex"
                Log.error(message)
                params.completion(.failure(.message(message)))
                return
                
            case .error(let error):
                let message = "Error looking up file in FileIndex: \(error)"
                Log.error(message)
                params.completion(.failure(.message(message)))
                return
            }
            
            if fileIndexObj.fileVersion != uploadDeletionRequest.fileVersion {
                let message = "File index version is: \(String(describing: fileIndexObj.fileVersion)), but you asked to delete version: \(String(describing: uploadDeletionRequest.fileVersion))"
                Log.error(message)
                params.completion(.failure(.message(message)))
                return
            }
            
            Log.debug("uploadDeletionRequest.actualDeletion: \(String(describing: uploadDeletionRequest.actualDeletion))")
            
#if DEBUG
            if let actualDeletion = uploadDeletionRequest.actualDeletion, actualDeletion {
                actuallyDeleteFileFromServer(key:key, uploadDeletionRequest:uploadDeletionRequest, fileIndexObj:fileIndexObj, params:params)
                return
            }
#endif

            var errorString:String?
            
            // Create entry in Upload table.
            let upload = Upload()
            upload.fileUUID = uploadDeletionRequest.fileUUID
            upload.deviceUUID = params.deviceUUID
            upload.fileVersion = uploadDeletionRequest.fileVersion
            upload.state = .toDeleteFromFileIndex
            upload.userId = params.currentSignedInUser!.userId
            upload.sharingGroupUUID = uploadDeletionRequest.sharingGroupUUID
            
            let uploadAddResult = params.repos.upload.add(upload: upload)
            
            switch uploadAddResult {
            case .success(_):
                let response = UploadDeletionResponse()
                params.completion(.success(response))
                return
                
            case .duplicateEntry:
                Log.info("File was already marked for deletion: Not adding again.")
                let response = UploadDeletionResponse()
                params.completion(.success(response))
                return
                
            case .aModelValueWasNil:
                errorString = "A model value was nil!"
                
            case .deadlock:
                errorString = "Deadlock"

            case .waitTimeout:
                errorString = "waitTimeout"
                
            case .otherError(let error):
                errorString = error
            }

            Log.error(errorString!)
            params.completion(.failure(.message(errorString!)))
            return
        }
    }
    
#if DEBUG
    func actuallyDeleteFileFromServer(key:FileIndexRepository.LookupKey, uploadDeletionRequest: Filenaming, fileIndexObj:FileIndex, params:RequestProcessingParameters) {
    
        let result = params.repos.fileIndex.retry {
            return params.repos.fileIndex.remove(key: key)
        }
        
        switch result {
        case .removed(numberRows: let numberRows):
            if numberRows != 1 {
                let message = "Number of rows deleted \(numberRows) != 1"
                Log.error(message)
                params.completion(.failure(.message(message)))
                return
            }
            
        case .deadlock:
            let message = "Error deleting from FileIndex: deadlock"
            Log.error(message)
            params.completion(.failure(.message(message)))
            return
        
        case .waitTimeout:
            let message = "Error deleting from FileIndex: waitTimeout"
            Log.error(message)
            params.completion(.failure(.message(message)))
            return
            
        case .error(let error):
            let message = "Error deleting from FileIndex: \(error)"
            Log.error(message)
            params.completion(.failure(.message(message)))
            return
        }
        
        // OWNER
        // Need to get creds for the user that uploaded the v0 file.
        guard let cloudStorageCreds = FileController.getCreds(forUserId: fileIndexObj.userId, from: params.db, delegate: params.accountDelegate)?.cloudStorage else {
            let message = "Could not obtain CloudStorage creds for original v0 owner of file."
            Log.error(message)
            params.completion(.failure(
                    .goneWithReason(message: message, .userRemoved)))
            return
        }

        let cloudFileName = uploadDeletionRequest.cloudFileName(deviceUUID: fileIndexObj.deviceUUID!, mimeType: fileIndexObj.mimeType!)
        
        // Because we need this to get the cloudFolderName
        guard let effectiveOwningUserCreds = params.effectiveOwningUserCreds else {
            let message = "No effectiveOwningUserCreds"
            Log.debug(message)
            params.completion(.failure(
                    .goneWithReason(message: message, .userRemoved)))
            return
        }
        
        let options = CloudStorageFileNameOptions(cloudFolderName: effectiveOwningUserCreds.cloudFolderName, mimeType: fileIndexObj.mimeType!)
        
        cloudStorageCreds.deleteFile(cloudFileName: cloudFileName, options: options) { result in
        
            switch result {
            case .success:
                break
            case .accessTokenRevokedOrExpired:
                // As in [1].
                Log.warning("Error deleting file from cloud storage: Access token revoked or expired")
                
            case .failure(let error):
                // [1]
                Log.warning("Error deleting file from cloud storage: \(error)!")
                // I'm not going to fail if this fails-- this is for debugging and it's not a big deal. Drop through and report success.
            }
            
            let response = UploadDeletionResponse()
            params.completion(.success(response))
            return
        }
    }
#endif
}
