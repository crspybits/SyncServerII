//
//  HealthCheck.swift
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

class HealthCheckRequest : NSObject, RequestMessage {
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

class HealthCheckResponse : ResponseMessage {
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
