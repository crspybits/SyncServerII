//
//  FileController+DownloadFile.swift
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
    func downloadFile(params:RequestProcessingParameters) {
        guard let downloadRequest = params.request as? DownloadFileRequest else {
            let message = "Did not receive DownloadFileRequest"
            Log.error(message)
            params.completion(.failure(.message(message)))
            return
        }
        
        guard sharingGroupSecurityCheck(sharingGroupUUID: downloadRequest.sharingGroupUUID, params: params) else {
            let message = "Failed in sharing group security check."
            Log.error(message)
            params.completion(.failure(.message(message)))
            return
        }
        
        // TODO: *0* What would happen if someone else deletes the file as we we're downloading it? It seems a shame to hold a lock for the entire duration of the download, however.
        
        // TODO: *0* Related question: With transactions, if we just select from a particular row (i.e., for the master version for this user, as immediately below) does this result in a lock for the duration of the transaction? We could test for this by sleeping in the middle of the download below, and seeing if another request could delete the file at the same time. This should make a good test case for any mechanism that I come up with.

        Controllers.getMasterVersion(sharingGroupUUID: downloadRequest.sharingGroupUUID, params: params) { (error, masterVersion) in
            if error != nil {
                params.completion(.failure(.message("\(error!)")))
                return
            }

            if masterVersion != downloadRequest.masterVersion {
                let response = DownloadFileResponse()
                Log.warning("Master version update: \(String(describing: masterVersion))")
                response.masterVersionUpdate = masterVersion
                params.completion(.success(response))
                return
            }
            
            // Need to get the file from the cloud storage service:
            
            // First, lookup the file in the FileIndex. This does an important security check too-- make sure the fileUUID is in the sharing group.
           
            let key = FileIndexRepository.LookupKey.primaryKeys(sharingGroupUUID: downloadRequest.sharingGroupUUID, fileUUID: downloadRequest.fileUUID)

            let lookupResult = params.repos.fileIndex.lookup(key: key, modelInit: FileIndex.init)
            
            var fileIndexObj:FileIndex?
            
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
                let message = "Could not find file in FileIndex"
                Log.error(message)
                params.completion(.failure(.message(message)))
                return
                
            case .error(let error):
                let message = "Error looking up file in FileIndex: \(error)"
                Log.error(message)
                params.completion(.failure(.message(message)))
                return
            }
            
            guard downloadRequest.fileVersion == fileIndexObj!.fileVersion else {
                let message = "Expected file version \(String(describing: downloadRequest.fileVersion)) was not the same as the actual version \(String(describing: fileIndexObj!.fileVersion))"
                Log.error(message)
                params.completion(.failure(.message(message)))
                return
            }
            
            guard downloadRequest.appMetaDataVersion == fileIndexObj!.appMetaDataVersion else {
                let message = "Expected app meta data version \(String(describing: downloadRequest.appMetaDataVersion)) was not the same as the actual version \(String(describing: fileIndexObj!.appMetaDataVersion))"
                Log.error(message)
                params.completion(.failure(.message(message)))
                return
            }
            
            if fileIndexObj!.deleted! {
                let message = "The file you are trying to download has been deleted!"
                Log.error(message)
                params.completion(.failure(.message(message)))
                return
            }
                        
            // TODO: *5*: Eventually, this should bypass the middle man and stream from the cloud storage service directly to the client.
            
            // Both the deviceUUID and the fileUUID must come from the file index-- They give the specific name of the file in cloud storage. The deviceUUID of the requesting device is not the right one.
            guard let deviceUUID = fileIndexObj!.deviceUUID else {
                let message = "No deviceUUID!"
                Log.error(message)
                params.completion(.failure(.message(message)))
                return
            }
            
            let cloudFileName = fileIndexObj!.cloudFileName(deviceUUID:deviceUUID, mimeType: fileIndexObj!.mimeType)

            // OWNER
            // The cloud storage for the file is the original owning user's storage.
            guard let owningUserCreds = FileController.getCreds(forUserId: fileIndexObj!.userId, from: params.db, delegate: params.accountDelegate) else {
                let message = "Could not obtain owning users creds"
                Log.error(message)
                params.completion(.failure(.message(message)))
                return
            }
            
            guard let cloudStorageCreds = owningUserCreds.cloudStorage,
                let cloudStorageType = owningUserCreds.accountScheme.cloudStorageType else {
                let message = "Could not obtain cloud storage creds or cloud storage type."
                Log.error(message)
                params.completion(.failure(.message(message)))
                return
            }
            
            let options = CloudStorageFileNameOptions(cloudFolderName: owningUserCreds.cloudFolderName, mimeType: fileIndexObj!.mimeType)
            
            cloudStorageCreds.downloadFile(cloudFileName: cloudFileName, options:options) { result in
                switch result {
                case .success(let data, let checkSum):
                    // I used to check the file size as downloaded against the file size in the file index (last uploaded). And call it an error if they didn't match. But we're being fancier now. Going to let the client see if this is an error. https://github.com/crspybits/SyncServerII/issues/93
                    
                    Log.debug("CheckSum: \(checkSum)")

                    var contentsChanged = false
                    // 11/4/18; This is conditional because for migration purposes, the FileIndex may not contain a lastUploadedCheckSum. i.e., it comes from a FileIndex record before we added the lastUploadedCheckSum field.
                    if let lastUploadedCheckSum = fileIndexObj!.lastUploadedCheckSum {
                        contentsChanged = checkSum != lastUploadedCheckSum
                    }
                    
                    let response = DownloadFileResponse()
                    response.appMetaData = fileIndexObj!.appMetaData
                    response.data = data
                    response.checkSum = checkSum
                    response.cloudStorageType = cloudStorageType
                    response.contentsChanged = contentsChanged
                    params.completion(.success(response))
                
                // Don't consider the following two cases as HTTP status errors, so we can return appMetaData back to client. appMetaData, for v0 files, can be necessary for clients to deal more completely with these error conditions.
                case .accessTokenRevokedOrExpired:
                    let message = "Access token revoked or expired."
                    Log.error(message)
                    let response = DownloadFileResponse()
                    response.appMetaData = fileIndexObj!.appMetaData
                    response.cloudStorageType = cloudStorageType
                    response.gone = GoneReason.authTokenExpiredOrRevoked.rawValue
                    params.completion(.success(response))
                    
                case .fileNotFound:
                    let message = "File not found."
                    Log.error(message)
                    let response = DownloadFileResponse()
                    response.appMetaData = fileIndexObj!.appMetaData
                    response.cloudStorageType = cloudStorageType
                    response.gone = GoneReason.fileRemovedOrRenamed.rawValue
                    params.completion(.success(response))
                
                case .failure(let error):
                    let message = "Failed downloading file: \(error)"
                    Log.error(message)
                    params.completion(.failure(.message(message)))
                }
            }            
        }
    }
}
