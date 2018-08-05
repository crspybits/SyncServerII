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
    // Make sure the current signed in user is a member of the sharing group.s
    func sharingGroupSecurityCheck(sharingGroupId: SharingGroupId, params:RequestProcessingParameters) -> Bool {
    
        guard let userId = params.currentSignedInUser?.userId else {
            Log.error("No userId!")
            return false
        }
        
        let sharingKey = SharingGroupUserRepository.LookupKey.primaryKeys(sharingGroupId: sharingGroupId, userId: userId)
        let lookupResult = params.repos.sharingGroupUser.lookup(key: sharingKey, modelInit: SharingGroupUser.init)
        
        switch lookupResult {
        case .found:
            return true
            
        case .noObjectFound:
            Log.error("User: \(userId) is not in sharing group: \(sharingGroupId)")
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
    
    let completion: (Response)->()
    
    init(request: RequestMessage, ep:ServerEndpoint, creds: Account?, effectiveOwningUserCreds: Account?, profileCreds: Account?, userProfile: UserProfile?, currentSignedInUser: User?, db:Database, repos:Repositories, routerResponse:RouterResponse, deviceUUID: String?, completion: @escaping (Response)->()) {
        self.request = request
        self.ep = ep
        self.creds = creds
        self.effectiveOwningUserCreds = effectiveOwningUserCreds
        self.profileCreds = profileCreds
        self.userProfile = userProfile
        self.currentSignedInUser = currentSignedInUser
        self.db = db
        self.repos = repos
        self.routerResponse = routerResponse
        self.deviceUUID = deviceUUID
        self.completion = completion
    }
}

public class Controllers {
    // When adding a new controller, you must add it to this list.
    private static let list:[ControllerProtocol.Type] =
        [UserController.self, UtilController.self, FileController.self, SharingAccountsController.self, SharingGroupsController.self]
    
    static func setup() -> Bool {
        for controller in list {
            if !controller.setup() {
                Log.error("Could not setup controller: \(controller)")
                return false
            }
        }
        
        return true
    }
}
