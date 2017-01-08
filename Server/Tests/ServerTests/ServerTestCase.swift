//
//  ServerTestCase.swift
//  Server
//
//  Created by Christopher Prince on 1/7/17.
//
//

import Foundation
import XCTest
@testable import Server

class ServerTestCase : XCTestCase {
    override func setUp() {
        Constants.delegate = self
        super.setUp()
    }
}

extension ServerTestCase : ConstantsDelegate {
    // A hack to get access to Server.plist during testing.
    public func plistFilePath(forConstants:Constants) -> String {
        return "/tmp"
    }
}

