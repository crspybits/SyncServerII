//
//  CheckCreds.swift
//  Server
//
//  Created by Christopher Prince on 11/26/16.
//
//

import Foundation
import PerfectLib
import Gloss
import Kitura

// Check to see if both primary and secondary authentication succeed.
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
    static let resultKey = "result"
    var result: PerfectLib.JSONConvertible?

    required init?(json: JSON) {
    }
    
    convenience init?() {
        self.init(json:[:])
    }
    
    // MARK: - Serialization
    func toJSON() -> JSON? {
        return jsonify([
            CheckCredsResponse.resultKey ~~> self.result
        ])
    }
}
