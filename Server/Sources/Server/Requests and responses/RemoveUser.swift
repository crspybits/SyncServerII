//
//  RemoveUser.swift
//  Server
//
//  Created by Christopher Prince on 12/23/16.
//
//

import Foundation
import PerfectLib
import Gloss
import Kitura

class RemoveUserRequest : NSObject, RequestMessage {
    // No specific user info is required here because the HTTP auth headers are used to identify the user to be removed. i.e., for now a user can only remove themselves.
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

class RemoveUserResponse : ResponseMessage {
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
