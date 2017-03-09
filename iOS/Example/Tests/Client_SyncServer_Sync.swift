//
//  Client_SyncServer_Sync.swift
//  SyncServer
//
//  Created by Christopher Prince on 3/6/17.
//  Copyright © 2017 CocoaPods. All rights reserved.
//

import XCTest
@testable import SyncServer
import SMCoreLib
import Foundation

class Client_SyncServer_Sync: TestCase {
    
    override func setUp() {
        super.setUp()
        DownloadFileTracker.removeAll()
        DirectoryEntry.removeAll()
        UploadFileTracker.removeAll()
        UploadQueue.removeAll()
        UploadQueues.removeAll()
        
        CoreData.sessionNamed(Constants.coreDataName).saveContext()

        removeAllServerFilesInFileIndex()
    }
    
    override func tearDown() {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
        super.tearDown()
    }

    func testThatSyncWithNoFilesResultsInSyncDone() {
        SyncServer.session.eventsDesired = .all

        let expectation1 = self.expectation(description: "test1")
        
        syncServerEventOccurred = {event in
            switch event {
            case .syncDone:
                expectation1.fulfill()
                
            default:
                XCTFail()
            }
        }
        
        SyncServer.session.sync()
        
        waitForExpectations(timeout: 10.0, handler: nil)
        
        getFileIndex(expectedFiles: [])
    }
    
    func testThatDoingSyncTwiceWithNoFilesResultsInTwoSyncDones() {
        SyncServer.session.eventsDesired = .all

        let expectation1 = self.expectation(description: "test1")
        let expectation2 = self.expectation(description: "test2")
        
        var count = 0
        
        syncServerEventOccurred = {event in
            switch event {
            case .syncDone:
                count += 1
                switch count {
                case 1:
                    expectation1.fulfill()
                    
                case 2:
                    expectation2.fulfill()
                    
                default:
                    XCTFail()
                }
                
            default:
                XCTFail()
            }
        }
        
        SyncServer.session.sync()
        SyncServer.session.sync()
        
        waitForExpectations(timeout: 10.0, handler: nil)
        
        getFileIndex(expectedFiles: [])
    }
    
    // TODO: *0* Do a sync with no uploads pending, but pending downloads.
}
