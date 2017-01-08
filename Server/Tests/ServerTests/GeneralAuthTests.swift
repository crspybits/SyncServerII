//
//  GeneralAuthTests.swift
//  Server
//
//  Created by Christopher Prince on 12/4/16.
//
//

import LoggerAPI
@testable import Server
import KituraNet
import XCTest

class GeneralAuthTests: ServerTestCase {
    func testBadEndpointFails() {
        performServerTest { expectation in
            let badRoute = ServerEndpoint("foobar", method: .post)
            self.performRequest(route:badRoute) { response, dict in
                XCTAssert(response!.statusCode != .OK, "Did not fail on request")
                Log.info("response.statusCode: \(response?.statusCode)")
                expectation.fulfill()
            }
        }
    }
    
    func testGoodEndpointWithNoCredsRequiredWorks() {
        performServerTest { expectation in
            self.performRequest(route: ServerEndpoints.healthCheck) { response, dict in
                XCTAssert(response!.statusCode == .OK, "Failed on healthcheck request")
                expectation.fulfill()
            }
        }
    }
}
