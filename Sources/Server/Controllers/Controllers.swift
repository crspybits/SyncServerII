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
    static func setup(db:Database) -> Bool
}

public struct RequestProcessingParameters {
    let request: RequestMessage!
    let ep: ServerEndpoint!
    
    // For secondary authenticated endpoints, these are the immediate user's creds (i.e., they are not the effective user id creds) read from the database. It's nil otherwise.
    let creds: Creds?
    
    // These reflect the effectiveOwningUserId of the User.
    let effectiveOwningUserCreds: Creds?

    // These are used only when we don't yet have database creds-- e.g., for endpoints that are creating users in the database.
    let profileCreds: Creds?
    
    let userProfile: UserProfile?
    let currentSignedInUser:User?
    let db:Database!
    let repos:Repositories!
    let routerResponse:RouterResponse!
    let deviceUUID:String?
    
    // Call the completion with a nil ResponseMessage if there was a fatal error processing the request, i.e., an error that could not be handled in the normal responses made in the ResponseMessage.
    let completion: (ResponseMessage?)->()
}

public class Controllers {
    // When adding a new controller, you must add it to this list.
    private static let list:[ControllerProtocol.Type] =
        [UserController.self, UtilController.self, FileController.self, SharingAccountsController.self]
    
    static func setup() -> Bool {
        let db = Database(showStartupInfo: true)
        for controller in list {
            if !controller.setup(db:db) {
                Log.error("Could not setup controller: \(controller)")
                return false
            }
        }
        
        return true
    }
}
