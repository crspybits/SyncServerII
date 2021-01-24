//
//  Startup.swift
//  AccountFileTests
//
//  Created by Christopher G Prince on 7/12/20.
//

import Foundation
import LoggerAPI

class Startup {
    static func halt(_ message: String) {
        Log.error(message)
        exit(1)
    }
}
