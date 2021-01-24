//
//  DatabaseLockTests.swift
//  DatabaseTests
//
//  Created by Christopher G Prince on 7/12/20.
//

import XCTest
@testable import Server
@testable import TestsCommon
import LoggerAPI
import HeliumLogger
import Foundation
import ServerShared

class DatabaseLockTests: ServerTestCase {
    let testLockName = "TestLock"
    
    override func setUp() {
        super.setUp()
        HeliumLogger.use(.debug)
    }
    
    override func tearDown() {
        super.tearDown()
    }

    func testSingleGetLock() throws {
        let result = try db.getLock(lockName: testLockName)
        Log.debug("testGetLock: \(result)")
        XCTAssert(result)
    }
    
    func testTwoGetLocksFail() throws {
        let result1 = try db.getLock(lockName: testLockName)
        XCTAssert(result1)
        
        // Second attempt must be on a different connection. If we use the same connection, it succeeds.
        guard let db2 = Database() else {
            XCTFail()
            return
        }
        
        let result2 = try db2.getLock(lockName: testLockName)
        XCTAssert(!result2)
    }
    
    func testGetLockAndReleaseLock() throws {
        let result1 = try db.getLock(lockName: testLockName)
        XCTAssert(result1)
        
        let result2 = try db.releaseLock(lockName: testLockName)
        XCTAssert(result2)
    }
}
