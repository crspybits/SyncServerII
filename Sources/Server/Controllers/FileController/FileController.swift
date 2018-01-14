//
//  FileController.swift
//  Server
//
//  Created by Christopher Prince on 1/15/17.
//
//

import Foundation
import LoggerAPI
import Credentials
import CredentialsGoogle
import SyncServerShared

class FileController : ControllerProtocol {
    // Don't do this setup in init so that database initalizations don't have to be done per endpoint call.
    class func setup(db:Database) -> Bool {
        if case .failure(_) = UploadRepository(db).upcreate() {
            return false
        }
        
        if case .failure(_) = FileIndexRepository(db).upcreate() {
            return false
        }
        
        if case .failure(_) = LockRepository(db).upcreate() {
            return false
        }
        
        return true
    }
    
    init() {
    }
    
    enum GetMasterVersionError : Error {
    case error(String)
    case noObjectFound
    }
    
    // Synchronous callback.
    func getMasterVersion(params:RequestProcessingParameters, completion:(Error?, MasterVersionInt?)->()) {
    
        // We need to get the master version for the effectiveSignedInUser because the master version reflects the version of the data for the owning user, not a sharing user.
        let effectiveOwningUserId = params.currentSignedInUser!.effectiveOwningUserId
        
        let key = MasterVersionRepository.LookupKey.userId(effectiveOwningUserId)
        let result = params.repos.masterVersion.lookup(key: key, modelInit: MasterVersion.init)
        
        switch result {
        case .error(let error):
            completion(GetMasterVersionError.error(error), nil)
            
        case .found(let model):
            let masterVersionObj = model as! MasterVersion
            completion(nil, masterVersionObj.masterVersion)
            
        case .noObjectFound:
            let errorMessage = "Master version record not found for: \(key)"
            Log.error(errorMessage)
            completion(GetMasterVersionError.noObjectFound, nil)
        }
    }
            
    func fileIndex(params:RequestProcessingParameters) {
        guard let fileIndexRequest = params.request as? FileIndexRequest else {
            Log.error("Did not receive FileIndexRequest")
            params.completion(nil)
            return
        }

#if DEBUG
        if fileIndexRequest.testServerSleep != nil {
            Log.info("Starting sleep (testServerSleep= \(fileIndexRequest.testServerSleep!)).")
            Thread.sleep(forTimeInterval: TimeInterval(fileIndexRequest.testServerSleep!))
            Log.info("Finished sleep (testServerSleep= \(fileIndexRequest.testServerSleep!)).")
        }
#endif
        
        getMasterVersion(params: params) { (error, masterVersion) in
            if error != nil {
                params.completion(nil)
                return
            }
            
            // Note that this uses the `effectiveOwningUserId`-- because we are concerned about the owning user's data.
            let fileIndexResult = params.repos.fileIndex.fileIndex(forUserId: params.currentSignedInUser!.effectiveOwningUserId)

            switch fileIndexResult {
            case .fileIndex(let fileIndex):
                Log.info("Number of entries in FileIndex: \(fileIndex.count)")
                let response = FileIndexResponse()!
                response.fileIndex = fileIndex
                response.masterVersion = masterVersion
                params.completion(response)
                
            case .error(let error):
                Log.error("Error: \(error)")
                params.completion(nil)
                return
            }
        }
    }
    
    func getUploads(params:RequestProcessingParameters) {
        guard params.request is GetUploadsRequest else {
            Log.error("Did not receive GetUploadsRequest")
            params.completion(nil)
            return
        }
        
        let uploadsResult = params.repos.upload.uploadedFiles(forUserId: params.currentSignedInUser!.userId, deviceUUID: params.deviceUUID!)

        switch uploadsResult {
        case .uploads(let uploads):
            let fileInfo = UploadRepository.uploadsToFileInfo(uploads: uploads)
            let response = GetUploadsResponse()!
            response.uploads = fileInfo
            params.completion(response)
            
        case .error(let error):
            Log.error("Error: \(error)")
            params.completion(nil)
            return
        }
    }
}
