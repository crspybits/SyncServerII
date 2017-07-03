//
//  HealthCheck.swift
//  SyncServer
//
//  Created by Christopher Prince on 12/25/16.
//  Copyright © 2016 Spastic Muffin, LLC. All rights reserved.
//

import XCTest
@testable import SyncServer

class ServerAPI_HealthCheck: XCTestCase {
    
    override func setUp() {
        super.setUp()
        ServerNetworking.session.authenticationDelegate = nil
    }
    
    override func tearDown() {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
        super.tearDown()
    }
    
    func testHealthCheckSucceeds() {
        let expectation = self.expectation(description: "health check")
        
        ServerAPI.session.healthCheck { error in
            XCTAssert(error == nil)
            expectation.fulfill()
        }
        
        waitForExpectations(timeout: 10.0, handler: nil)
    }
}
