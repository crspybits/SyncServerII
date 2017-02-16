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

protocol ControllerProtocol {
    static func setup(db:Database) -> Bool
}

public struct RequestProcessingParameters {
    let request: RequestMessage!
    let creds: Creds?
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
        [UserController.self, UtilController.self, FileController.self]
    
    static func setup() -> Bool {
        let db = Database()
        for controller in list {
            if !controller.setup(db:db) {
                Log.error("Could not setup controller: \(controller)")
                return false
            }
        }
        
        return true
    }
}
