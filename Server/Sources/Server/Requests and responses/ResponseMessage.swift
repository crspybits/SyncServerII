//
//  ResponseMessage.swift
//  Server
//
//  Created by Christopher Prince on 11/27/16.
//
//

import Foundation
import Gloss

public protocol ResponseMessage : Encodable, Decodable {
    init?(json: JSON)
}

