//
//  CheckCreds.swift
//  Server
//
//  Created by Christopher Prince on 11/26/16.
//
//

import Foundation
import Gloss

#if SERVER
import Kitura
#endif

// Check to see if both primary and secondary authentication succeed. i.e., check to see if a user exists.

class CheckCredsRequest : NSObject, RequestMessage {
    required init?(json: JSON) {
        super.init()
    }
    
#if SERVER
    required init?(request: RouterRequest) {
        super.init()
    }
#endif

    func toJSON() -> JSON? {
        return jsonify([
        ])
    }
}

class CheckCredsResponse : ResponseMessage {
    // This will be present iff the user is a sharing user. i.e., for an owning user it will be nil.
    static let sharingPermissionKey = "sharingPermission"
    var sharingPermission:SharingPermission!
    
    public var responseType: ResponseType {
        return .json
    }
    
    required init?(json: JSON) {
        self.sharingPermission = Decoder.decodeSharingPermission(key: CheckCredsResponse.sharingPermissionKey, json: json)
    }
    
    convenience init?() {
        self.init(json:[:])
    }
    
    // MARK: - Serialization
    func toJSON() -> JSON? {
        return jsonify([
            Encoder.encodeSharingPermission(key: CheckCredsResponse.sharingPermissionKey, value: self.sharingPermission)
        ])
    }
}
