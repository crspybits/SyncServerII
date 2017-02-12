//
//  AddUser.swift
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

class AddUserRequest : NSObject, RequestMessage {
#if SERVER
    required convenience init?(request: RouterRequest) {
        self.init(json: request.queryParameters)
    }
#endif
    
    required init?(json: JSON) {
        super.init()
    }
    
    func toJSON() -> JSON? {
        return jsonify([
        ])
    }
}

class AddUserResponse : ResponseMessage {
    public var responseType: ResponseType {
        return .json
    }
    
    required init?(json: JSON) {
    }
    
    convenience init?() {
        self.init(json:[:])
    }
    
    // MARK: - Serialization
    func toJSON() -> JSON? {
        return jsonify([
        ])
    }
}
