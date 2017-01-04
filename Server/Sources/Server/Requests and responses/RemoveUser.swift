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

class RemoveUserRequest : NSObject, RequestMessage {
    required init?(json: JSON) {
        super.init()
    }
}

class RemoveUserResponse : ResponseMessage {
    static let resultKey = "result"
    var result: PerfectLib.JSONConvertible?

    // MARK: - Serialization
    func toJSON() -> JSON? {
        return jsonify([
            AddUserResponse.resultKey ~~> self.result,
        ])
    }
}
