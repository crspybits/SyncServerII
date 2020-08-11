//
//  FileController+DownloadAppMetaData.swift
//  Server
//
//  Created by Christopher G Prince on 3/23/18.
//

import Foundation
import LoggerAPI
import ServerShared

extension FileController {    
    func downloadAppMetaData(params:RequestProcessingParameters) {
        guard let downloadAppMetaDataRequest = params.request as? DownloadAppMetaDataRequest else {
            let message = "Did not receive DownloadAppMetaDataRequest"
            Log.error(message)
            params.completion(.failure(.message(message)))
            return
        }
        
        guard sharingGroupSecurityCheck(sharingGroupUUID: downloadAppMetaDataRequest.sharingGroupUUID, params: params) else {
            let message = "Failed in sharing group security check."
            Log.error(message)
            params.completion(.failure(.message(message)))
            return
        }
            
        // Need to get the app meta data from the file index.

        // First, lookup the file in the FileIndex. This does an important security check too-- makes sure the fileUUID is in the sharing group.
        let key = FileIndexRepository.LookupKey.primaryKeys(sharingGroupUUID: downloadAppMetaDataRequest.sharingGroupUUID, fileUUID: downloadAppMetaDataRequest.fileUUID)
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
        
        if fileIndexObj!.deleted! {
            let message = "The file you are trying to download app meta data for has been deleted!"
            Log.error(message)
            params.completion(.failure(.message(message)))
            return
        }
        
        let response = DownloadAppMetaDataResponse()
        response.appMetaData = fileIndexObj.appMetaData
        params.completion(.success(response))
    }
}
