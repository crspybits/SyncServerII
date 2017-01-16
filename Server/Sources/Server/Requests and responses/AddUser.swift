//
//  AddUser.swift
//  Server
//
//  Created by Christopher Prince on 11/26/16.
//
//

import Foundation
import PerfectLib
import Gloss
import Kitura

class AddUserRequest : NSObject, RequestMessage {
    /*
    static let mobileDeviceUUIDKey = "mobileDeviceUUID"
    var mobileDeviceUUID:Foundation.UUID?
    
    static let cloudFolderPathKey = "cloudFolderPath"
    var cloudFolderPath:String?
    */
    
    // static let keys = [mobileDeviceUUIDKey, cloudFolderPathKey]
    
    required init?(request: RouterRequest) {
        super.init()
    }
    
    required init?(json: JSON) {
        super.init()
        
        /*
        self.mobileDeviceUUID = AddUserRequest.mobileDeviceUUIDKey <~~ json
        self.cloudFolderPath = AddUserRequest.cloudFolderPathKey <~~ json
        
        if !self.propertiesHaveValues(propertyNames: AddUserRequest.keys) {
            return nil
        }*/
    }
}

class AddUserResponse : ResponseMessage {
    static let resultKey = "result"
    var result: PerfectLib.JSONConvertible?

    // MARK: - Serialization
    func toJSON() -> JSON? {
        return jsonify([
            AddUserResponse.resultKey ~~> self.result,
        ])
    }
}
