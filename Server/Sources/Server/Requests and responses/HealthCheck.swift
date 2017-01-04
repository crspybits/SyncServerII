//
//  HealthCheck.swift
//  Server
//
//  Created by Christopher Prince on 11/26/16.
//
//

import Foundation
import PerfectLib
import Gloss

class HealthCheckRequest : NSObject, RequestMessage {
    required init?(json: JSON) {
        super.init()
    }
}

class HealthCheckResponse : ResponseMessage {
    static let resultKey = "result"
    var result: PerfectLib.JSONConvertible?

    // MARK: - Serialization
    func toJSON() -> JSON? {
        return jsonify([
        ])
    }
}
