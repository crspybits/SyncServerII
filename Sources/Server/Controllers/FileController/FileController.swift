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
    static func checkForExistingFile(params:RequestProcessingParameters, sharingGroupUUID: String, fileUUID: String) throws -> FileIndex? {
        
        let key = FileIndexRepository.LookupKey.primaryKeys(sharingGroupUUID: sharingGroupUUID, fileUUID: fileUUID)

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
    
    // OWNER
    static func getCreds(forUserId userId: UserId, from db: Database, delegate: AccountDelegate) -> Account? {
        let userKey = UserRepository.LookupKey.userId(userId)
        let userResults = UserRepository(db).lookup(key: userKey, modelInit: User.init)
        guard case .found(let model) = userResults,
            let user = model as? User else {
            Log.error("Could not get user from database.")
            return nil
        }
    
        guard var creds = user.credsObject else {
            Log.error("Could not get user creds.")
            return nil
        }
        
        creds.delegate = delegate
        
        return creds
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

        guard let groups = params.repos.sharingGroup.sharingGroups(forUserId: params.currentSignedInUser!.userId, sharingGroupUserRepo: params.repos.sharingGroupUser, userRepo: params.repos.user) else {
            let message = "Could not get sharing groups for user."
            Log.error(message)
            params.completion(.failure(.message(message)))
            return
        }
        
        let clientSharingGroups:[SyncServerShared.SharingGroup] = groups.map { serverGroup in
            return serverGroup.toClient()
        }
        
        guard let sharingGroupUUID = indexRequest.sharingGroupUUID else {
            // Not an error-- caller just didn't give a sharing group uuid-- only returning sharing group info.
            let response = IndexResponse()
            response.sharingGroups = clientSharingGroups
            params.completion(.success(response))
            return
        }
        
        Log.info("Index: Getting file index for sharing group uuid: \(sharingGroupUUID)")

        // Not worrying about whether the sharing group is deleted-- where's the harm in getting a file index for a deleted sharing group?
        guard sharingGroupSecurityCheck(sharingGroupUUID: sharingGroupUUID, params: params, checkNotDeleted: false) else {
            let message = "Failed in sharing group security check."
            Log.error(message)
            params.completion(.failure(.message(message)))
            return
        }
        
        guard params.repos.sharingGroupLock.lock(sharingGroupUUID: sharingGroupUUID) else {
            let message = "Error acquiring lock!"
            Log.debug(message)
            params.completion(.failure(.message(message)))
            return
        }
        
        Controllers.getMasterVersion(sharingGroupUUID: sharingGroupUUID, params: params) { (error, masterVersion) in
            
            let fileIndexResult = params.repos.fileIndex.fileIndex(forSharingGroupUUID: sharingGroupUUID)

            switch fileIndexResult {
            case .fileIndex(let fileIndex):
                Log.info("Number of entries in FileIndex: \(fileIndex.count)")
                let response = IndexResponse()
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
        
        guard sharingGroupSecurityCheck(sharingGroupUUID: getUploadsRequest.sharingGroupUUID, params: params) else {
            let message = "Failed in sharing group security check."
            Log.error(message)
            params.completion(.failure(.message(message)))
            return
        }
        
        let uploadsResult = params.repos.upload.uploadedFiles(forUserId: params.currentSignedInUser!.userId, sharingGroupUUID: getUploadsRequest.sharingGroupUUID, deviceUUID: params.deviceUUID!)

        switch uploadsResult {
        case .uploads(let uploads):
            let fileInfo = UploadRepository.uploadsToFileInfo(uploads: uploads)
            let response = GetUploadsResponse()
            response.uploads = fileInfo
            params.completion(.success(response))
            
        case .error(let error):
            let message = "Error: \(String(describing: error))"
            Log.error(message)
            params.completion(.failure(.message(message)))
            return
        }
    }
}
