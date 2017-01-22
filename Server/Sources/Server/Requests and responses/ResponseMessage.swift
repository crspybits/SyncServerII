//
//  ResponseMessage.swift
//  Server
//
//  Created by Christopher Prince on 11/27/16.
//
//

import Foundation
import PerfectLib
import Gloss

public protocol ResponseMessage : Encodable, Decodable {
    var result: JSONConvertible? {get set}
    init?(json: JSON)
}

