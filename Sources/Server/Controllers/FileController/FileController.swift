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
    enum CheckError : Error {
        case couldNotConvertModelObject
        case errorLookingUpInFileIndex
    }
    
    // Result is nil if there is no existing file in the FileIndex. Throws an error if there is an error.
    static func checkForExistingFile(params:RequestProcessingParameters, sharingGroupId: SharingGroupId, fileUUID: String) throws -> FileIndex? {
        
        let key = FileIndexRepository.LookupKey.primaryKeys(sharingGroupId: sharingGroupId, fileUUID: fileUUID)

        let lookupResult = params.repos.fileIndex.lookup(key: key, modelInit: FileIndex.init)

        switch lookupResult {
        case .found(let modelObj):
            guard let fileIndexObj = modelObj as? FileIndex else {
                Log.error("Could not convert model object to FileIndex")
                throw CheckError.couldNotConvertModelObject
            }
            
            return fileIndexObj
            
        case .noObjectFound:
            return nil
            
        case .error(let error):
            Log.error("Error looking up file in FileIndex: \(error)")
            throw CheckError.errorLookingUpInFileIndex
        }
    }
    
    class func setup() -> Bool {
        return true
    }
    
    init() {
    }
    
    enum GetMasterVersionError : Error {
    case error(String)
    case noObjectFound
    }
    
    // Synchronous callback.
    // Get the master version for a sharing group because the master version reflects the overall version of the data for a sharing group.
    func getMasterVersion(sharingGroupId: SharingGroupId, params:RequestProcessingParameters, completion:(Error?, MasterVersionInt?)->()) {
        
        let key = MasterVersionRepository.LookupKey.sharingGroupId(sharingGroupId)
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
    
    // OWNER
    static func getCreds(forUserId userId: UserId, from db: Database) -> Account? {
        let userKey = UserRepository.LookupKey.userId(userId)
        let userResults = UserRepository(db).lookup(key: userKey, modelInit: User.init)
        guard case .found(let model) = userResults,
            let user = model as? User else {
            Log.error("Could not get user from database.")
            return nil
        }
    
        guard let creds = user.credsObject else {
            Log.error("Could not get user creds.")
            return nil
        }
        
        return creds
    }
    
    // Make sure all uploaded files for the current signed in user belong to the given sharing group.
    func checkSharingGroupConsistency(sharingGroupId: SharingGroupId, params:RequestProcessingParameters) -> Bool? {
        let fileUploadsResult = params.repos.upload.uploadedFiles(forUserId: params.currentSignedInUser!.userId, deviceUUID: params.deviceUUID!)
        switch fileUploadsResult {
        case .uploads(let uploads):
            let filteredResult = uploads.filter({$0.sharingGroupId == sharingGroupId})
            if filteredResult.count == uploads.count {
                return true
            }
            else {
                return false
            }
            
        case .error(let error):
            Log.error("Failed to get file uploads: \(error)")
            return nil
        }
    }
            
    func index(params:RequestProcessingParameters) {
        guard let indexRequest = params.request as? IndexRequest else {
            let message = "Did not receive IndexRequest"
            Log.error(message)
            params.completion(.failure(.message(message)))
            return
        }

#if DEBUG
        if indexRequest.testServerSleep != nil {
            Log.info("Starting sleep (testServerSleep= \(indexRequest.testServerSleep!)).")
            Thread.sleep(forTimeInterval: TimeInterval(indexRequest.testServerSleep!))
            Log.info("Finished sleep (testServerSleep= \(indexRequest.testServerSleep!)).")
        }
#endif

        guard let groups = params.repos.sharingGroup.sharingGroups(forUserId: params.currentSignedInUser!.userId) else {
            let message = "Could not get sharing groups for user."
            Log.error(message)
            params.completion(.failure(.message(message)))
            return
        }
        
        let clientSharingGroups:[SyncServerShared.SharingGroup] = groups.map { serverGroup in
            let clientGroup = SyncServerShared.SharingGroup()!
            clientGroup.sharingGroupId = serverGroup.sharingGroupId
            clientGroup.sharingGroupName = serverGroup.sharingGroupName
            clientGroup.deleted = serverGroup.deleted
            return clientGroup
        }
        
        guard let sharingGroupId = indexRequest.sharingGroupId else {
            // Not an error-- caller just didn't give a sharing group id-- only returning sharing group info.
            let response = IndexResponse()!
            response.sharingGroups = clientSharingGroups
            params.completion(.success(response))
            return
        }
        
        Log.info("Index: Getting file index for sharing group id: \(sharingGroupId)")

        // Not worrying about whether the sharing group is deleted-- where's the harm in getting a file index for a deleted sharing group?
        guard sharingGroupSecurityCheck(sharingGroupId: sharingGroupId, params: params, checkNotDeleted: false) else {
            let message = "Failed in sharing group security check."
            Log.error(message)
            params.completion(.failure(.message(message)))
            return
        }
        
        let lock = Lock(sharingGroupId:sharingGroupId, deviceUUID:params.deviceUUID!)
        switch params.repos.lock.lock(lock: lock) {
        case .success:
            break
        
        case .lockAlreadyHeld:
            let message = "Error: Lock already held!"
            Log.debug(message)
            params.completion(.failure(.message(message)))
            return
        
        case .errorRemovingStaleLocks, .modelValueWasNil, .otherError:
            let message = "Error removing locks!"
            Log.debug(message)
            params.completion(.failure(.message(message)))
            return
        }
        
        getMasterVersion(sharingGroupId: sharingGroupId, params: params) { (error, masterVersion) in
            if error != nil {
                params.repos.lock.unlock(sharingGroupId: sharingGroupId)
                params.completion(.failure(.message("\(error!)")))
                return
            }
            
            let fileIndexResult = params.repos.fileIndex.fileIndex(forSharingGroupId: sharingGroupId)
            
            if !params.repos.lock.unlock(sharingGroupId: sharingGroupId) {
                let message = "Error in unlock!"
                Log.debug(message)
                params.completion(.failure(.message(message)))
                return
            }

            switch fileIndexResult {
            case .fileIndex(let fileIndex):
                Log.info("Number of entries in FileIndex: \(fileIndex.count)")
                let response = IndexResponse()!
                response.fileIndex = fileIndex
                response.masterVersion = masterVersion
                response.sharingGroups = clientSharingGroups
                params.completion(.success(response))
                
            case .error(let error):
                let message = "Error: \(error)"
                Log.error(message)
                params.completion(.failure(.message(message)))
                return
            }
        }
    }
    
    func getUploads(params:RequestProcessingParameters) {
        guard let getUploadsRequest = params.request as? GetUploadsRequest else {
            let message = "Did not receive GetUploadsRequest"
            Log.error(message)
            params.completion(.failure(.message(message)))
            return
        }
        
        guard sharingGroupSecurityCheck(sharingGroupId: getUploadsRequest.sharingGroupId, params: params) else {
            let message = "Failed in sharing group security check."
            Log.error(message)
            params.completion(.failure(.message(message)))
            return
        }
        
        guard let consistentSharingGroups = checkSharingGroupConsistency(sharingGroupId: getUploadsRequest.sharingGroupId, params:params), consistentSharingGroups else {
            let message = "Inconsistent sharing groups."
            Log.error(message)
            params.completion(.failure(.message(message)))
            return
        }
        
        let uploadsResult = params.repos.upload.uploadedFiles(forUserId: params.currentSignedInUser!.userId, deviceUUID: params.deviceUUID!)

        switch uploadsResult {
        case .uploads(let uploads):
            let fileInfo = UploadRepository.uploadsToFileInfo(uploads: uploads)
            let response = GetUploadsResponse()!
            response.uploads = fileInfo
            params.completion(.success(response))
            
        case .error(let error):
            let message = "Error: \(error)"
            Log.error(message)
            params.completion(.failure(.message(message)))
            return
        }
    }
}
