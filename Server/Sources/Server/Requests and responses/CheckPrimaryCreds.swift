//
//  CheckPrimaryCreds.swift
//  Server
//
//  Created by Christopher Prince on 12/17/16.
//
//

import Foundation
import PerfectLib
import Gloss
import Kitura

class CheckPrimaryCredsRequest : NSObject, RequestMessage {
    required init?(request: RouterRequest) {
        super.init()
    }
    
    required init?(json: JSON) {
        super.init()
    }
    
    func toJSON() -> JSON? {
        return jsonify([
        ])
    }
}

class CheckPrimaryCredsResponse : ResponseMessage {
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
        ])
    }
}
