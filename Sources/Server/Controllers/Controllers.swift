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
import ServerShared
import ServerAccount
import ServerAppleSignInAccount

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

public class RequestProcessingParameters: FinishUploadsParameters {
    let request: RequestMessage!
    let ep: ServerEndpoint!
    
    // For secondary authenticated endpoints, these are the immediate user's creds (i.e., they are not the effective user id creds) read from the database. It's nil otherwise.
    let creds: Account?
    
    // [1]. These reflect the effectiveOwningUserId of the User, if any. They will be nil if (a) the user was invited, (b) they redeemed their sharing invitation with a non-owning account, and (c) their original inviting user removed their own account.
    let effectiveOwningUserCreds: Account?

    // These are used only when we don't yet have database creds-- e.g., for endpoints that are creating users in the database.
    let profileCreds: Account?
    
    let userProfile: UserProfile?
    let accountProperties:AccountProperties?
    let currentSignedInUser:User?
    let db:Database!
    var repos:Repositories!
    let routerResponse:RouterResponse!
    let deviceUUID:String?
    let services:Services
    let accountDelegate: AccountDelegate
    
    enum Response {
        case success(ResponseMessage)
        
        case successWithRunner(ResponseMessage, runner: RequestHandler.PostRequestRunner?)
        
        // Fatal error processing the request, i.e., an error that could not be handled in the normal responses made in the ResponseMessage.
        case failure(RequestHandler.FailureResult?)
    }
    
    let completion: (Response)->()
    
    init(request: RequestMessage, ep:ServerEndpoint, creds: Account?, effectiveOwningUserCreds: Account?, profileCreds: Account?, userProfile: UserProfile?, accountProperties: AccountProperties?, currentSignedInUser: User?, db:Database, repos:Repositories, routerResponse:RouterResponse, deviceUUID: String?, services: Services, accountDelegate: AccountDelegate, completion: @escaping (Response)->()) {
    
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
        self.services = services
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
        [UserController.self,
        UtilController.self,
        FileController.self,
        SharingAccountsController.self,
        SharingGroupsController.self,
        PushNotificationsController.self,
        AppleServerToServerNotifications.self]
    
    static func setup() -> Bool {
        for controller in list {
            if !controller.setup() {
                Log.error("Could not setup controller: \(controller)")
                return false
            }
        }
        
        return true
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
