//
//  GeneralAuthTests.swift
//  Server
//
//  Created by Christopher Prince on 12/4/16.
//
//

import LoggerAPI
@testable import Server
@testable import TestsCommon
import KituraNet
import XCTest
import Foundation
import ServerShared

class GeneralAuthTests: ServerTestCase {

    func testBadEndpointFails() {
        performServerTest { expectation, creds in
            let badRoute = ServerEndpoint("foobar", method: .post, requestMessageType: AddUserRequest.self)
            self.performRequest(route:badRoute) { response, dict in
                XCTAssert(response!.statusCode != .OK, "Did not fail on request")
                Log.info("response.statusCode: \(String(describing: response?.statusCode))")
                expectation.fulfill()
            }
        }
    }
    
    func testGoodEndpointWithNoCredsRequiredWorks() {
        performServerTest { expectation, creds in
            self.performRequest(route: ServerEndpoints.healthCheck) { response, dict in
                XCTAssert(response!.statusCode == .OK, "Failed on healthcheck request")
                expectation.fulfill()
            }
        }
    }
}

