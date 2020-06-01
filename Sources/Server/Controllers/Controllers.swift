//
//  Controllers.swift
//  Server
//
//  Created by Christopher Prince on 12/5/16.
//
//

import Foundation
import LoggerAPI
import Credentials
import Kitura
import SyncServerShared

protocol ControllerProtocol {
    static func setup() -> Bool
}

extension ControllerProtocol {
    // Make sure the current signed in user is a member of the sharing group.
    // `checkNotDeleted` set to true ensures the sharing group is not deleted.
    func sharingGroupSecurityCheck(sharingGroupUUID: String, params:RequestProcessingParameters, checkNotDeleted: Bool = true) -> Bool {
    
        guard let userId = params.currentSignedInUser?.userId else {
            Log.error("No userId!")
            return false
        }
        
        let sharingUserKey = SharingGroupUserRepository.LookupKey.primaryKeys(sharingGroupUUID: sharingGroupUUID, userId: userId)
        let lookupResult = params.repos.sharingGroupUser.lookup(key: sharingUserKey, modelInit: SharingGroupUser.init)
        
        switch lookupResult {
        case .found:
            if checkNotDeleted {
                // The deleted flag is in the SharingGroup (not SharingGroupUser) repo. Need to look that up.
                let sharingKey = SharingGroupRepository.LookupKey.sharingGroupUUID(sharingGroupUUID)
                let lookupResult = params.repos.sharingGroup.lookup(key: sharingKey, modelInit: SharingGroup.init)
                switch lookupResult {
                case .found(let modelObj):
                    guard let sharingGroup = modelObj as? Server.SharingGroup else {
                        Log.error("Could not convert model obj to SharingGroup.")
                        return false
                    }
                    
                    guard !sharingGroup.deleted else {
                        return false
                    }
                    
                case .noObjectFound:
                    Log.error("Could not find sharing group.")

                case .error(let error):
                    Log.error("Error looking up sharing group: \(error)")
                }
            }
            
            return true
            
        case .noObjectFound:
            Log.error("User: \(userId) is not in sharing group: \(sharingGroupUUID)")
            return false
            
        case .error(let error):
            Log.error("Error checking if user is in sharing group: \(error)")
            return false
        }
    }
}

public class RequestProcessingParameters {
    let request: RequestMessage!
    let ep: ServerEndpoint!
    
    // For secondary authenticated endpoints, these are the immediate user's creds (i.e., they are not the effective user id creds) read from the database. It's nil otherwise.
    let creds: Account?
    
    // [1]. These reflect the effectiveOwningUserId of the User, if any. They will be nil if (a) the user was invited, (b) they redeemed their sharing invitation with a non-owning account, and (c) their original inviting user removed their own account.
    let effectiveOwningUserCreds: Account?

    // These are used only when we don't yet have database creds-- e.g., for endpoints that are creating users in the database.
    let profileCreds: Account?
    
    let userProfile: UserProfile?
    let accountProperties:AccountManager.AccountProperties?
    let currentSignedInUser:User?
    let db:Database!
    var repos:Repositories!
    let routerResponse:RouterResponse!
    let deviceUUID:String?
    
    enum Response {
        case success(ResponseMessage)
        
        // Fatal error processing the request, i.e., an error that could not be handled in the normal responses made in the ResponseMessage.
        case failure(RequestHandler.FailureResult?)
    }
    
    let accountDelegate: AccountDelegate
    let completion: (Response)->()
    
    init(request: RequestMessage, ep:ServerEndpoint, creds: Account?, effectiveOwningUserCreds: Account?, profileCreds: Account?, userProfile: UserProfile?, accountProperties: AccountManager.AccountProperties?, currentSignedInUser: User?, db:Database, repos:Repositories, routerResponse:RouterResponse, deviceUUID: String?, accountDelegate: AccountDelegate, completion: @escaping (Response)->()) {
        self.request = request
        self.ep = ep
        self.creds = creds
        self.effectiveOwningUserCreds = effectiveOwningUserCreds
        self.profileCreds = profileCreds
        self.userProfile = userProfile
        self.accountProperties = accountProperties
        self.currentSignedInUser = currentSignedInUser
        self.db = db
        self.repos = repos
        self.routerResponse = routerResponse
        self.deviceUUID = deviceUUID
        self.completion = completion
        self.accountDelegate = accountDelegate
    }
    
    func fail(_ message: String) {
        Log.error(message)
        completion(.failure(.message(message)))
    }
}

public class Controllers {
    // When adding a new controller, you must add it to this list.
    private static let list:[ControllerProtocol.Type] =
        [UserController.self, UtilController.self, FileController.self, SharingAccountsController.self, SharingGroupsController.self, PushNotificationsController.self]
    
    static func setup() -> Bool {
        for controller in list {
            if !controller.setup() {
                Log.error("Could not setup controller: \(controller)")
                return false
            }
        }
        
        return true
    }
    
    enum UpdateMasterVersionResult : Error, RetryRequest {
        case success
        case error(String)
        case masterVersionUpdate(MasterVersionInt)
        
        case deadlock
        case waitTimeout
        
        var shouldRetry: Bool {
            if case .deadlock = self {
                return true
            }
            else if case .waitTimeout = self {
                return true
            }
            else {
                return false
            }
        }
    }
    
    private static func updateMasterVersion(sharingGroupUUID:String, currentMasterVersion:MasterVersionInt, params:RequestProcessingParameters) -> UpdateMasterVersionResult {

        let currentMasterVersionObj = MasterVersion()
        
        // The master version reflects a sharing group.
        currentMasterVersionObj.sharingGroupUUID = sharingGroupUUID
        
        currentMasterVersionObj.masterVersion = currentMasterVersion
        let updateMasterVersionResult = params.repos.masterVersion.updateToNext(current: currentMasterVersionObj)
        
        var result:UpdateMasterVersionResult!
        
        switch updateMasterVersionResult {
        case .success:
            result = .success
            
        case .error(let error):
            let message = "Failed lookup in MasterVersionRepository: \(error)"
            Log.error(message)
            result = .error(message)
            
        case .deadlock:
            result = .deadlock
            
        case .waitTimeout:
            result = .waitTimeout
            
        case .didNotMatchCurrentMasterVersion:
            getMasterVersion(sharingGroupUUID: sharingGroupUUID, params: params) { (error, masterVersion) in
                if error == nil {
                    result = .masterVersionUpdate(masterVersion!)
                }
                else {
                    result = .error("\(error!)")
                }
            }
        }
        
        return result
    }
    
    enum GetMasterVersionError : Error {
    case error(String)
    case noObjectFound
    }
    
    // Synchronous callback.
    // Get the master version for a sharing group because the master version reflects the overall version of the data for a sharing group.
    static func getMasterVersion(sharingGroupUUID: String, params:RequestProcessingParameters, completion:(Error?, MasterVersionInt?)->()) {
        
        let key = MasterVersionRepository.LookupKey.sharingGroupUUID(sharingGroupUUID)
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
    
    enum MasterVersionResult {
        case success(MasterVersionInt)
        case error(Error?)
    }
    
    static func getMasterVersion(sharingGroupUUID: String, params:RequestProcessingParameters) -> MasterVersionResult {
        var result: MasterVersionResult = .error(nil)
        
        getMasterVersion(sharingGroupUUID: sharingGroupUUID, params: params) { error, masterVersion in
            if let error = error {
                result = .error(error)
            }
            else if let masterVersion = masterVersion {
                result = .success(masterVersion)
            }
        }
        
        return result
    }
    
    // Returns nil on success.
    static func updateMasterVersion(sharingGroupUUID: String, masterVersion: MasterVersionInt, params:RequestProcessingParameters, responseType: MasterVersionUpdateResponse.Type?) -> RequestProcessingParameters.Response? {
    
        let updateResult = params.repos.masterVersion.retry {
            return updateMasterVersion(sharingGroupUUID: sharingGroupUUID, currentMasterVersion: masterVersion, params: params)
        }
                
        switch updateResult {
        case .success:
            return nil

        case .masterVersionUpdate(let updatedMasterVersion):
            Log.warning("Master version update: \(updatedMasterVersion)")
            if let responseType = responseType {
                var response = responseType.init()
                response.masterVersionUpdate = updatedMasterVersion
                return .success(response)
            }
            else {
                let message = "Master version update but no response type was given."
                Log.error(message)
                return .failure(.message(message))
            }
            
        case .deadlock:
            return .failure(.message("Deadlock!"))

        case .waitTimeout:
            return .failure(.message("Timeout!"))
            
        case .error(let error):
            let message = "Failed on updateMasterVersion: \(error)"
            Log.error(message)
            return .failure(.message(message))
        }
    }
    
    enum EffectiveOwningUserId {
        case found(UserId)
        case noObjectFound
        case gone
        case error
    }
    
    static func getEffectiveOwningUserId(user: User, sharingGroupUUID: String, sharingGroupUserRepo: SharingGroupUserRepository) -> EffectiveOwningUserId {
        
        if AccountScheme(.accountName(user.accountType))?.userType == .owning {
            return .found(user.userId)
        }
        
        let sharingUserKey = SharingGroupUserRepository.LookupKey.primaryKeys(sharingGroupUUID: sharingGroupUUID, userId: user.userId)
        let lookupResult = sharingGroupUserRepo.lookup(key: sharingUserKey, modelInit: SharingGroupUser.init)
        
        switch lookupResult {
        case .found(let model):
            let sharingGroupUser = model as! SharingGroupUser
            if let owningUserId = sharingGroupUser.owningUserId {
                return .found(owningUserId)
            }
            else {
                return .gone
            }
            
        case .noObjectFound:
            return .noObjectFound
            
        case .error(let error):
            Log.error("getEffectiveOwningUserIds: \(error)")
            return .error
        }
    }
}
