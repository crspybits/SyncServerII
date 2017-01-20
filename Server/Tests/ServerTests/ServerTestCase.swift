//
//  ServerTestCase.swift
//  Server
//
//  Created by Christopher Prince on 1/7/17.
//
//

// Base XCTestCase class- has no specific tests.

import Foundation
import XCTest
@testable import Server
import LoggerAPI

class ServerTestCase : XCTestCase {
    override func setUp() {
        Constants.delegate = self
        super.setUp()
    }
    
    func addNewUser() {
        self.performServerTest { expectation, googleCreds in
            let headers = self.setupHeaders(accessToken: googleCreds.accessToken)
            self.performRequest(route: ServerEndpoints.addUser, headers: headers) { response, dict in
                Log.info("Status code: \(response!.statusCode)")
                XCTAssert(response!.statusCode == .OK, "Did not work on addUser request")
                expectation.fulfill()
            }
        }
    }
}

extension ServerTestCase : ConstantsDelegate {
    // A hack to get access to Server.json during testing.
    public func configFilePath(forConstants:Constants) -> String {
        return "/tmp"
    }
}

