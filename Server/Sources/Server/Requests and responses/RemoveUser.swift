//
//  RemoveUser.swift
//  Server
//
//  Created by Christopher Prince on 12/23/16.
//
//

import Foundation
import Gloss

#if SERVER
import Kitura
#endif

class RemoveUserRequest : NSObject, RequestMessage {
    // No specific user info is required here because the HTTP auth headers are used to identify the user to be removed. i.e., for now a user can only remove themselves.
    required init?(json: JSON) {
        super.init()
    }
    
#if SERVER
    required convenience init?(request: RouterRequest) {
        self.init(json: request.queryParameters)
    }
#endif
    
    func toJSON() -> JSON? {
        return jsonify([
        ])
    }
}

class RemoveUserResponse : ResponseMessage {
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
