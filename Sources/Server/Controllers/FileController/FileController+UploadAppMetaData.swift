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
            params.completion(.failure(nil))
            return
        }
        
        guard sharingGroupSecurityCheck(sharingGroupUUID: uploadAppMetaDataRequest.sharingGroupUUID, params: params) else {
            Log.error("Failed in sharing group security check.")
            params.completion(.failure(nil))
            return
        }
        
        Controllers.getMasterVersion(sharingGroupUUID: uploadAppMetaDataRequest.sharingGroupUUID, params: params) { error, masterVersion in
            if error != nil {
                let message = "Error: \(String(describing: error))"
                Log.error(message)
                params.completion(.failure(.message(message)))
                return
            }

            if masterVersion != uploadAppMetaDataRequest.masterVersion {
                let response = UploadAppMetaDataResponse()
                Log.warning("Master version update: \(String(describing: masterVersion))")
                response.masterVersionUpdate = masterVersion
                params.completion(.success(response))
                return
            }
            
            // Make sure this file is already present in the FileIndex.
            var existingFileInFileIndex:FileIndex?
            do {
                existingFileInFileIndex = try FileController.checkForExistingFile(params:params, sharingGroupUUID: uploadAppMetaDataRequest.sharingGroupUUID, fileUUID:uploadAppMetaDataRequest.fileUUID)
            } catch (let error) {
                let message = "Could not lookup file in FileIndex: \(error)"
                Log.error(message)
                params.completion(.failure(.message(message)))
                return
            }
            
            guard existingFileInFileIndex != nil else {
                let message = "File not found in FileIndex!"
                Log.error(message)
                params.completion(.failure(.message(message)))
                return
            }
            
            // Undeletion is not possible for an appMetaData upload because the file contents have been removed (on a prior upload deletion) and the appMetaData upload can't replace those file contents.
            if existingFileInFileIndex!.deleted {
                let message = "Attempt to upload app meta data for an existing file, but it has already been deleted."
                Log.error(message)
                params.completion(.failure(.message(message)))
                return
            }
        
            guard UploadRepository.isValidAppMetaDataUpload(
                currServerAppMetaDataVersion: existingFileInFileIndex!.appMetaDataVersion,
                currServerAppMetaData:
                    existingFileInFileIndex!.appMetaData,
                upload:uploadAppMetaDataRequest.appMetaData) else {
                let message = "App meta data or version is not valid for upload."
                Log.error(message)
                params.completion(.failure(.message(message)))
                return
            }
            
            let upload = Upload()
            upload.deviceUUID = params.deviceUUID
            upload.fileUUID = uploadAppMetaDataRequest.fileUUID
            upload.state = .uploadingAppMetaData
            upload.userId = params.currentSignedInUser!.userId
            upload.appMetaData = uploadAppMetaDataRequest.appMetaData!.contents
            upload.appMetaDataVersion = uploadAppMetaDataRequest.appMetaData!.version
            upload.sharingGroupUUID = uploadAppMetaDataRequest.sharingGroupUUID
            
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
                
            case .deadlock:
                errorString = "Deadlock"

            case .waitTimeout:
                errorString = "WaitTimeout"
                
            case .otherError(let error):
                errorString = error
            }
            
            if errorString != nil {
                Log.error(errorString!)
                params.completion(.failure(.message(errorString!)))
                return
            }

            let response = UploadAppMetaDataResponse()
            params.completion(.success(response))
        }
    }
}

