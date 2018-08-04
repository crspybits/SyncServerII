//
//  SharingGroupsControllerTests.swift
//  ServerTests
//
//  Created by Christopher G Prince on 7/15/18.
//

import XCTest
@testable import Server
import LoggerAPI
import Foundation
import SyncServerShared

class SharingGroupsControllerTests: ServerTestCase, LinuxTestable {
    override func setUp() {
        super.setUp()
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }
    
    override func tearDown() {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
        super.tearDown()
    }
    
    func testCreateSharingGroupWorks() {
    
    }
}

extension SharingGroupsControllerTests {
    static var allTests : [(String, (SharingGroupsControllerTests) -> () throws -> Void)] {
        return [
            ("testCreateSharingGroupWorks", testCreateSharingGroupWorks)
        ]
    }
    
    func testLinuxTestSuiteIncludesAllTests() {
        linuxTestSuiteIncludesAllTests(testType: SharingGroupsControllerTests.self)
    }
}
