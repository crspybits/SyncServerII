//
//  Client_SyncServer_Error.swift
//  SyncServer
//
//  Created by Christopher Prince on 4/2/17.
//  Copyright © 2017 Spastic Muffin, LLC. All rights reserved.
//

import XCTest
@testable import SyncServer
import SMCoreLib
import Foundation

class Client_SyncServer_Error: TestCase {
    override func setUp() {
        super.setUp()
        resetFileMetaData()
    }
    
    override func tearDown() {
        super.tearDown()
    }
    
    func testSyncFailure() {
        ServerAPI.session.failNextEndpoint = true
        
        SyncServer.session.eventsDesired = []
        let errorExp = self.expectation(description: "errorExp")

        syncServerErrorOccurred = { error in
            errorExp.fulfill()
        }
        
        SyncServer.session.sync()
        
        waitForExpectations(timeout: 10.0, handler: nil)
    }
    
    // TODO: *0* We need to test failure and recovery at various points throughout the client process. E.g., failure on a download.
    // TODO: *0* We also need to test: (a) failure, (b) intervening operations by other client, (c) and recovery.
    
    /*
    func testSyncFailureAndRetryWorks() {
    }
    */
}
