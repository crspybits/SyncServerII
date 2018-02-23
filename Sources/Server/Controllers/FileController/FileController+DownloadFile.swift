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

extension FileController {
    func downloadFile(params:RequestProcessingParameters) {
        guard let downloadRequest = params.request as? DownloadFileRequest else {
            Log.error("Did not receive DownloadFileRequest")
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
                Log.warning("Master version update: \(String(describing: masterVersion))")
                response.masterVersionUpdate = masterVersion
                params.completion(response)
                return
            }

            guard let cloudStorageCreds = params.effectiveOwningUserCreds as? CloudStorage else {
                Log.error("Could not obtain CloudStorage Creds")
                params.completion(nil)
                return
            }
            
            // Need to get the file from the cloud storage service:
            
            // First, lookup the file in the FileIndex. This does an important security check too-- makes sure the owning userId corresponds to the fileUUID.
            let key = FileIndexRepository.LookupKey.primaryKeys(userId: "\(params.currentSignedInUser!.effectiveOwningUserId)", fileUUID: downloadRequest.fileUUID)

            let lookupResult = params.repos.fileIndex.lookup(key: key, modelInit: FileIndex.init)
            
            var fileIndexObj:FileIndex?
            
            switch lookupResult {
            case .found(let modelObj):
                fileIndexObj = modelObj as? FileIndex
                if fileIndexObj == nil {
                    Log.error("Could not convert model object to FileIndex")
                    params.completion(nil)
                    return
                }
                
            case .noObjectFound:
                Log.error("Could not find file in FileIndex")
                params.completion(nil)
                return
                
            case .error(let error):
                Log.error("Error looking up file in FileIndex: \(error)")
                params.completion(nil)
                return
            }
            
            guard downloadRequest.fileVersion == fileIndexObj!.fileVersion else {
                Log.error("Expected file version \(downloadRequest.fileVersion) was not the same as the actual version \(fileIndexObj!.fileVersion)")
                params.completion(nil)
                return
            }
            
            if fileIndexObj!.deleted! {
                Log.error("The file you are trying to download has been deleted!")
                params.completion(nil)
                return
            }
            
            // TODO: *5*: Eventually, this should bypass the middle man and stream from the cloud storage service directly to the client.
            
            // Both the deviceUUID and the fileUUID must come from the file index-- They give the specific name of the file in cloud storage. The deviceUUID of the requesting device is not the right one.
            guard let deviceUUID = fileIndexObj!.deviceUUID else {
                Log.error("No deviceUUID!")
                params.completion(nil)
                return
            }
            
            let cloudFileName = fileIndexObj!.cloudFileName(deviceUUID:deviceUUID, mimeType: fileIndexObj!.mimeType)
            
            // Because we need this to get the cloudFolderName
            guard params.effectiveOwningUserCreds != nil else {
                Log.debug("No effectiveOwningUserCreds")
                params.completion(nil)
                return
            }
            
            let options = CloudStorageFileNameOptions(cloudFolderName: params.effectiveOwningUserCreds!.cloudFolderName, mimeType: fileIndexObj!.mimeType)
            
            cloudStorageCreds.downloadFile(cloudFileName: cloudFileName, options:options) { result in
                switch result {
                case .success(let data):
                    if Int64(data.count) != fileIndexObj!.fileSizeBytes {
                        Log.error("Actual file size \(data.count) was not the same as that expected \(fileIndexObj!.fileSizeBytes)")
                        params.completion(nil)
                        return
                    }
                    
                    let response = DownloadFileResponse()!
                    response.appMetaData = fileIndexObj!.appMetaData
                    response.data = data
                    response.fileSizeBytes = Int64(data.count)
                    
                    params.completion(response)
                    return
                
                case .failure(let error):
                    Log.error("Failed downloading file: \(error)")
                    params.completion(nil)
                    return
                }
            }            
        }
    }
}
