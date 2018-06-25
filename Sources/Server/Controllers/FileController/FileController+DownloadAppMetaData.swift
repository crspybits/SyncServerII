//
//  FileController+DownloadAppMetaData.swift
//  Server
//
//  Created by Christopher G Prince on 3/23/18.
//

import Foundation
import LoggerAPI
import SyncServerShared

extension FileController {    
    func downloadAppMetaData(params:RequestProcessingParameters) {
        guard let downloadAppMetaDataRequest = params.request as? DownloadAppMetaDataRequest else {
            Log.error("Did not receive DownloadAppMetaDataRequest")
            params.completion(nil)
            return
        }
        
        guard sharingGroupSecurityCheck(sharingGroupId: downloadAppMetaDataRequest.sharingGroupId, params: params) else {
            Log.error("Failed in sharing group security check.")
            params.completion(nil)
            return
        }
        
        getMasterVersion(sharingGroupId: downloadAppMetaDataRequest.sharingGroupId, params: params) { (error, masterVersion) in
            if error != nil {
                params.completion(nil)
                return
            }

            if masterVersion != downloadAppMetaDataRequest.masterVersion {
                let response = DownloadAppMetaDataResponse()!
                Log.warning("Master version update: \(String(describing: masterVersion))")
                response.masterVersionUpdate = masterVersion
                params.completion(response)
                return
            }
            
            // Need to get the app meta data from the file index.

            // First, lookup the file in the FileIndex. This does an important security check too-- makes sure the fileUUID is in the sharing group.
            let key = FileIndexRepository.LookupKey.primaryKeys(sharingGroupId: downloadAppMetaDataRequest.sharingGroupId, fileUUID: downloadAppMetaDataRequest.fileUUID)
            let lookupResult = params.repos.fileIndex.lookup(key: key, modelInit: FileIndex.init)
            
            var fileIndexObj:FileIndex!
            
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
            
            if fileIndexObj!.deleted! {
                Log.error("The file you are trying to download app meta data for has been deleted!")
                params.completion(nil)
                return
            }
            
            guard let fileIndexAppMetaDataVersion = fileIndexObj.appMetaDataVersion else {
                Log.error("Nil app meta data version in FileIndex.")
                params.completion(nil)
                return
            }
            
            guard downloadAppMetaDataRequest.appMetaDataVersion == fileIndexAppMetaDataVersion else {
                Log.error("Expected app meta data version \(downloadAppMetaDataRequest.appMetaDataVersion) was not the same as the actual version \(fileIndexAppMetaDataVersion)")
                params.completion(nil)
                return
            }
            
            let response = DownloadAppMetaDataResponse()!
            response.appMetaData = fileIndexObj.appMetaData
            params.completion(response)
        }
    }
}
