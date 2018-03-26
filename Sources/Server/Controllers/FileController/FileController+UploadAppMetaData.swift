//
//  FileController+UploadAppMetaData.swift
//  Server
//
//  Created by Christopher G Prince on 3/23/18.
//

import Foundation
import LoggerAPI
import SyncServerShared

extension FileController {    
    func uploadAppMetaData(params:RequestProcessingParameters) {
        guard let uploadAppMetaDataRequest = params.request as? UploadAppMetaDataRequest else {
            Log.error("Did not receive UploadAppMetaDataRequest")
            params.completion(nil)
            return
        }
        
        getMasterVersion(params: params) { error, masterVersion in
            if error != nil {
                Log.error("Error: \(String(describing: error))")
                params.completion(nil)
                return
            }

            if masterVersion != uploadAppMetaDataRequest.masterVersion {
                let response = UploadAppMetaDataResponse()!
                Log.warning("Master version update: \(String(describing: masterVersion))")
                response.masterVersionUpdate = masterVersion
                params.completion(response)
                return
            }
            
            // Make sure this file is already present in the FileIndex.
            var existingFileInFileIndex:FileIndex?
            do {
                existingFileInFileIndex = try FileController.checkForExistingFile(params:params, fileUUID:uploadAppMetaDataRequest.fileUUID)
            } catch (let error) {
                Log.error("Could not lookup file in FileIndex: \(error)")
                params.completion(nil)
                return
            }
            
            guard existingFileInFileIndex != nil else {
                Log.error("File not found in FileIndex!")
                params.completion(nil)
                return
            }
            
            if existingFileInFileIndex!.deleted {
                Log.error("Attempt to upload app meta data for an existing file, but it has already been deleted.")
                params.completion(nil)
                return
            }
        
            guard UploadRepository.isValidAppMetaDataUpload(
                currServerAppMetaDataVersion: existingFileInFileIndex!.appMetaDataVersion,
                currServerAppMetaData:
                    existingFileInFileIndex!.appMetaData,
                upload:uploadAppMetaDataRequest.appMetaData) else {
                Log.error("App meta data or version is not valid for upload.")
                params.completion(nil)
                return
            }
            
            let upload = Upload()
            upload.deviceUUID = params.deviceUUID
            upload.fileUUID = uploadAppMetaDataRequest.fileUUID
            upload.state = .uploadingAppMetaData
            upload.userId = params.currentSignedInUser!.userId
            upload.appMetaData = uploadAppMetaDataRequest.appMetaData!.contents
            upload.appMetaDataVersion = uploadAppMetaDataRequest.appMetaData!.version
            
            var errorString:String?
            
            let addUploadResult = params.repos.upload.add(upload: upload, fileInFileIndex: true)
            
            switch addUploadResult {
            case .success:
                break
                
            case .duplicateEntry:
                // Not considering this an error for client recovery purposes.
                break
                
            case .aModelValueWasNil:
                errorString = "A model value was nil!"
                
            case .otherError(let error):
                errorString = error
            }
            
            if errorString != nil {
                Log.error(errorString!)
                params.completion(nil)
                return
            }

            let response = UploadAppMetaDataResponse()!
            params.completion(response)
        }
    }
}

