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
    
    required init?(request: RouterRequest) {
        super.init()
    }
    
    func toJSON() -> JSON? {
        return jsonify([
        ])
    }
}

class CheckCredsResponse : ResponseMessage {
    // TODO: *2* If this is a sharing user, return back to the caller their sharing permissions-- so the UI can restrict itself accordingly.
    
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
