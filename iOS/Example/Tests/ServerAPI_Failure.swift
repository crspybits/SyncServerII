//
//  ServerAPI_Failure.swift
//  SyncServer
//
//  Created by Christopher Prince on 6/25/17.
//  Copyright © 2017 Spastic Muffin, LLC. All rights reserved.
//

import XCTest
@testable import SyncServer
import SMCoreLib

class ServerAPI_Failure: TestCase {
    
    override func setUp() {
        super.setUp()
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }
    
    override func tearDown() {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
        super.tearDown()
    }
    
    // The intent of this test is really to make sure that the number of db connections  opened/closed is the same even if the client goes away before the server call is done. And within this, really wanting to ensure that we don't have server threads that will never be released/ended. Currently this number of db connections opened/closed needs to be assessed visually.
    func testExample() {
        let expectation = self.expectation(description: "file index")

        var gotCallback = false
        fileIndexServerSleep = 5
        ServerAPI.session.fileIndex { (fileIndex, masterVersion, error) in
            gotCallback = true
        }

        TimedCallback.withDuration(1.0) {
            expectation.fulfill()
        }
        
        XCTAssert(gotCallback == false)
        
        waitForExpectations(timeout: 20.0, handler: nil)
    }
}
