//
//  SpecificDatabaseTests_SharingGroupLock.swift
//  ServerTests
//
//  Created by Christopher G Prince on 7/6/19.
//

import XCTest
@testable import Server
import LoggerAPI
import HeliumLogger
import Foundation
import SyncServerShared

class SpecificDatabaseTests_SharingGroupLock: ServerTestCase, LinuxTestable {
    override func setUp() {
        super.setUp()
    }

    override func tearDown() {
        super.tearDown()
    }
    
    func addSharingGroupLock(sharingGroupUUID: String) -> Bool {
        let result = SharingGroupLockRepository(db).add(sharingGroupUUID: sharingGroupUUID)
        
        switch result {
        case .success:
            return true
        
        default:
            XCTFail()
        }
        
        return false
    }

    func testAddLockRow() {
        let sharingGroupUUID = UUID().uuidString
        guard addSharingGroupLock(sharingGroupUUID: sharingGroupUUID) else {
            XCTFail()
            return
        }
    }
    
    func testLock() {
        let sharingGroupUUID = UUID().uuidString
        guard addSharingGroupLock(sharingGroupUUID: sharingGroupUUID) else {
            XCTFail()
            return
        }
        
        guard SharingGroupLockRepository(db).lock(sharingGroupUUID: sharingGroupUUID) else {
            XCTFail()
            return
        }
    }
}

extension SpecificDatabaseTests_SharingGroupLock {
    static var allTests : [(String, (SpecificDatabaseTests_SharingGroupLock) -> () throws -> Void)] {
        return [
            ("testAddLockRow", testAddLockRow),
            ("testLock", testLock)
        ]
    }
    
    func testLinuxTestSuiteIncludesAllTests() {
        linuxTestSuiteIncludesAllTests(testType: SpecificDatabaseTests_SharingGroupLock.self)
    }
}
