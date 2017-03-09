//
//  Client_SyncServer_UploadDeletion.swift
//  SyncServer
//
//  Created by Christopher Prince on 3/7/17.
//  Copyright © 2017 CocoaPods. All rights reserved.
//

import XCTest
@testable import SyncServer
import SMCoreLib
import Foundation

class Client_SyncServer_UploadDeletion: TestCase {
    
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
    
    func testThatUploadDeletionWorksWhenWaitUntilAfterUpload() {
        let (_, attr) = uploadSingleFileUsingSync()
        
        SyncServer.session.eventsDesired = [.syncDone, .uploadDeletionsCompleted, .singleUploadDeletionComplete]
        
        let expectation1 = self.expectation(description: "test1")
        let expectation2 = self.expectation(description: "test2")
        let expectation3 = self.expectation(description: "test3")
        
        syncServerEventOccurred = {event in
            switch event {
            case .syncDone:
                expectation1.fulfill()
            
            case .uploadDeletionsCompleted(numberOfFiles: let number):
                XCTAssert(number == 1)
                expectation2.fulfill()
                
            case .singleUploadDeletionComplete(fileUUID: let fileUUID):
                XCTAssert(attr.fileUUID == fileUUID)
                expectation3.fulfill()
                
            default:
                XCTFail()
            }
        }
        
        try! SyncServer.session.delete(fileUUID: attr.fileUUID)
        SyncServer.session.sync()
        
        waitForExpectations(timeout: 20.0, handler: nil)

        // Need to make sure the file is marked as deleted on the server.
        let fileIndex = getFileIndex(expectedFiles: [(fileUUID: attr.fileUUID, fileSize: nil)])
        XCTAssert(fileIndex[0].deleted)
    }
    
    // TODO: Make sure that, after the upload deletion, the directory entry for the file is marked as deleted
    
    // TODO: Attempt to delete an unknown UUID.
    
    // TODO: Attempt to delete a file that was already deleted on the server.
    
    // TODO: Attempt to delete a file that has a queued upload deletion.
    
    // TODO: Delete a file that has a queued (but not yet synced) file upload-- that queued file upload should be removed.
    
    // TODO: Attempt to delete a file with a version different than on the server. i.e., the local directory version is V1, but the server version is V2, V2 != V1. (This will have to wait until we have multi-version file support).
}
