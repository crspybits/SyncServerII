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
import Foundation
import SyncServerShared

class HealthCheckTests: ServerTestCase, LinuxTestable {
    override func setUp() {
        super.setUp()        
    }
    
    func testThatHealthCheckReturnsExpectedInfo() {
        healthCheck()
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

