//
//  FailureTests.swift
//  Server
//
//  Created by Christopher Prince on 4/2/17.
//
//

import LoggerAPI
@testable import Server
@testable import TestsCommon
import KituraNet
import XCTest
import Foundation
import ServerShared

class FailureTests: ServerTestCase {
    override func setUp() {
        super.setUp()
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }
    
    override func tearDown() {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
        super.tearDown()
    }

    func testThatHealthCheckFailsWhenRequested() {
        performServerTest { expectation, creds in
            let headers = [
                ServerConstants.httpRequestEndpointFailureTestKey: "true"
            ]
            self.performRequest(route: ServerEndpoints.healthCheck, headers:headers) { response, dict in
                XCTAssert(response!.statusCode == .internalServerError, "Did not fail on healthcheck request: \(response!.statusCode)")
                expectation.fulfill()
            }
        }
    }
}

