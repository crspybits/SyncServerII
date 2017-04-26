//
//  FileController+UploadDeletion.swift
//  Server
//
//  Created by Christopher Prince on 3/22/17.
//
//

import Foundation
import PerfectLib

extension FileController {
    func uploadDeletion(params:RequestProcessingParameters) {
        guard let uploadDeletionRequest = params.request as? UploadDeletionRequest else {
            Log.error(message: "Did not receive UploadDeletionRequest")
            params.completion(nil)
            return
        }
        
        getMasterVersion(params: params) { (error, masterVersion) in
            if error != nil {
                Log.error(message: "Error: \(String(describing: error))")
                params.completion(nil)
                return
            }

            if masterVersion != uploadDeletionRequest.masterVersion {
                let response = UploadDeletionResponse()!
                Log.warning(message: "Master version update: \(String(describing: masterVersion))")
                response.masterVersionUpdate = masterVersion
                params.completion(response)
                return
            }
            
            // Check whether this fileUUID exists in the FileIndex.
            // Note that we don't explicitly need to additionally check if our userId matches that in the FileIndex-- the following lookup does that security check for us.

            let key = FileIndexRepository.LookupKey.primaryKeys(userId: "\(params.currentSignedInUser!.effectiveOwningUserId)", fileUUID: uploadDeletionRequest.fileUUID)
            
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

            var errorString:String?
            
            // Create entry in Upload table.
            let upload = Upload()
            upload.fileUUID = uploadDeletionRequest.fileUUID
            upload.deviceUUID = params.deviceUUID
            upload.fileVersion = uploadDeletionRequest.fileVersion
            upload.state = .toDeleteFromFileIndex
            upload.userId = params.currentSignedInUser!.userId
            
            let uploadAddResult = params.repos.upload.add(upload: upload)
            
            switch uploadAddResult {
            case .success(_):
                let response = UploadDeletionResponse()!
                params.completion(response)
                return
                
            case .duplicateEntry:
                Log.info(message: "File was already marked for deletion: Not adding again.")
                let response = UploadDeletionResponse()!
                params.completion(response)
                return
                
            case .aModelValueWasNil:
                errorString = "A model value was nil!"
                
            case .otherError(let error):
                errorString = error
            }

            Log.error(message: errorString!)
            params.completion(nil)
            return
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
        
        guard let googleCreds = params.effectiveOwningUserCreds as? GoogleCreds else {
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
