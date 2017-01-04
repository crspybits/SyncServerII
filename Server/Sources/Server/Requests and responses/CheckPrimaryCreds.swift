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

class CheckPrimaryCredsRequest : NSObject, RequestMessage {
    required init?(json: JSON) {
        super.init()
    }
}

class CheckPrimaryCredsResponse : ResponseMessage {
    static let resultKey = "result"
    var result: PerfectLib.JSONConvertible?

    // MARK: - Serialization
    func toJSON() -> JSON? {
        return jsonify([
        ])
    }
}
