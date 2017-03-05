//
//  CoreDataTests.swift
//  SyncServer
//
//  Created by Christopher Prince on 2/25/17.
//  Copyright © 2017 CocoaPods. All rights reserved.
//

import XCTest
@testable import SyncServer
import SMCoreLib

class CoreDataTests: TestCase {
    
    override func setUp() {
        super.setUp()
        
        UploadFileTracker.removeAll()
        UploadQueue.removeAll()
        UploadQueues.removeAll()
        
        CoreData.sessionNamed(Constants.coreDataName).saveContext()
    }
    
    override func tearDown() {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
        super.tearDown()
    }
    
    func testLocalURLOnDownloadFileTracker() {
        let obj = DownloadFileTracker.newObject() as! DownloadFileTracker
        obj.localURL = SMRelativeLocalURL(withRelativePath: "foobar", toBaseURLType: .documentsDirectory)
        XCTAssert(obj.localURL != nil)
    }
    
    func testThatUploadFileTrackersWorks() {
        let uq = UploadQueue.newObject() as! UploadQueue
        XCTAssert(uq.uploadFileTrackers.count == 0)
    }
    
    func testThatPendingSyncQueueIsInitiallyEmpty() {
        XCTAssert(Upload.pendingSync().uploads!.count == 0)
    }
    
    func addObjectToPendingSync() {
        let uft = UploadFileTracker.newObject() as! UploadFileTracker
        Upload.pendingSync().addToUploads(uft)
    }
    
    func testThatPendingSyncQueueCanAddObject() {
        addObjectToPendingSync()
        CoreData.sessionNamed(Constants.coreDataName).saveContext()
        XCTAssert(Upload.pendingSync().uploads!.count == 1)
    }
    
    func testThatSyncedInitiallyIsEmpty() {
        XCTAssert(Upload.synced().queues!.count == 0)
    }
    
    func testMovePendingSyncToSynced() {
        addObjectToPendingSync()
        Upload.movePendingSyncToSynced()
        CoreData.sessionNamed(Constants.coreDataName).saveContext()
        
        XCTAssert(Upload.synced().queues!.count == 1)
    }
    
    func testThatGetHeadSyncQueueWorks() {
        addObjectToPendingSync()
        Upload.movePendingSyncToSynced()
        CoreData.sessionNamed(Constants.coreDataName).saveContext()
        
        guard let uploadQueue = Upload.getHeadSyncQueue() else {
            XCTFail()
            return
        }
        
        XCTAssert(uploadQueue.uploads!.count == 1)
    }
    
    func testThatRemoveHeadSyncQueueWorks() {
        addObjectToPendingSync()
        Upload.movePendingSyncToSynced()
        Upload.removeHeadSyncQueue()
        CoreData.sessionNamed(Constants.coreDataName).saveContext()
        
        XCTAssert(Upload.synced().queues!.count == 0)
    }
}
