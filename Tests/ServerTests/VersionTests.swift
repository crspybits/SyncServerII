//
//  VersionTests.swift
//  Server
//
//  Created by Christopher Prince on 2/3/18.
//
//

import XCTest
@testable import Server
import LoggerAPI
import Foundation
import SyncServerShared

class VersionTests: ServerTestCase, LinuxTestable {
    override func setUp() {
        super.setUp()        
    }
    
    func testThatVersionGetsReturnedInHeaders() {
        performServerTest { expectation, creds in
            // Use healthCheck just because it's a simple endpoint.
            self.performRequest(route: ServerEndpoints.healthCheck) { response, dict in
                XCTAssert(response!.statusCode == .OK, "Failed on healthcheck request")

                // It's a bit odd, but Kitura gives a [String] for each http header key.
                guard let versionHeaderArray = response?.headers[ServerConstants.httpResponseCurrentServerVersion], versionHeaderArray.count == 1 else {
                    XCTFail()
                    expectation.fulfill()
                    return
                }
                
                let versionString = versionHeaderArray[0]
                
                let components = versionString.components(separatedBy: ".")
                guard components.count == 3 else {
                    XCTFail("Didn't get three components in version: \(versionString)")
                    expectation.fulfill()
                    return
                }
                
                guard let _ = Int(components[0]),
                    let _ = Int(components[1]),
                    let _ = Int(components[2]) else {
                    XCTFail("All components were not integers: \(versionString)")
                    expectation.fulfill()
                    return
                }
                
                expectation.fulfill()
            }
        }
    }
}

extension VersionTests {
    static var allTests : [(String, (VersionTests) -> () throws -> Void)] {
        return [
            ("testThatVersionGetsReturnedInHeaders", testThatVersionGetsReturnedInHeaders),
        ]
    }
    
    func testLinuxTestSuiteIncludesAllTests() {
        linuxTestSuiteIncludesAllTests(testType: VersionTests.self)
    }
}

