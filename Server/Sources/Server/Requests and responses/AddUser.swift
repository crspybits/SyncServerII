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

class AddUserResponse : ResponseMessage {
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
            AddUserResponse.resultKey ~~> self.result,
        ])
    }
}
