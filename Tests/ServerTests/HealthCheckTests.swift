//
//  HealthCheckTests.swift
//  Server
//
//  Created by Christopher Prince on 12/28/17.
//
//

import XCTest
@testable import Server
import LoggerAPI
import PerfectLib
import Foundation
import SyncServerShared

class HealthCheckTests: ServerTestCase, LinuxTestable {
    override func setUp() {
        super.setUp()        
    }
    
    func testThatHealthCheckReturnsExpectedInfo() {
        performServerTest { expectation, creds in
            self.performRequest(route: ServerEndpoints.healthCheck) { response, dict in
                XCTAssert(response!.statusCode == .OK, "Failed on healthcheck request")
                
                guard let dict = dict, let healthCheckResponse = HealthCheckResponse(json: dict) else {
                    XCTFail()
                    return
                }
                
                XCTAssert(healthCheckResponse.serverUptime > 0)
                XCTAssert(healthCheckResponse.deployedGitTag.count > 0)
                XCTAssert(healthCheckResponse.currentServerDateTime != nil)

                expectation.fulfill()
            }
        }
    }
}

extension HealthCheckTests {
    static var allTests : [(String, (HealthCheckTests) -> () throws -> Void)] {
        return [
            ("testThatHealthCheckReturnsExpectedInfo", testThatHealthCheckReturnsExpectedInfo),
        ]
    }
    
    func testLinuxTestSuiteIncludesAllTests() {
        linuxTestSuiteIncludesAllTests(testType: HealthCheckTests.self)
    }
}

