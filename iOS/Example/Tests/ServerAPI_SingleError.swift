//
//  ServerAPI_SingleError.swift
//  SyncServer
//
//  Created by Christopher Prince on 4/5/17.
//  Copyright © 2017 CocoaPods. All rights reserved.
//

import XCTest
@testable import SyncServer
import SMCoreLib

// Testing retry mechanism: A single server error should not be enough to make the operation fail.

class ServerAPI_SingleError: TestCase {
    
    override func setUp() {
        super.setUp()
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }
    
    override func tearDown() {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
        super.tearDown()
    }
    
    func apiCallSingleError(singleError:Bool=true, runTest:(XCTestExpectation)->()) {
        if singleError {
            ServerAPI.session.failNextEndpoint = true
        }
        
        let expectation = self.expectation(description: "expectation")
        runTest(expectation)
        waitForExpectations(timeout: 40.0, handler: nil)
    }

    func testHealthCheckSingleError() {
        apiCallSingleError() { exp in
            ServerAPI.session.healthCheck { error in
                XCTAssert(error == nil)
                exp.fulfill()
            }
        }
    }
}
