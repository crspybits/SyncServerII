//
//  DoneUploads.swift
//  SyncServer
//
//  Created by Christopher Prince on 1/31/17.
//  Copyright © 2017 CocoaPods. All rights reserved.
//

import XCTest
@testable import SyncServer
import SMCoreLib

class ServerAPI_DoneUploads: TestCase {    
    override func setUp() {
        super.setUp()
    }
    
    override func tearDown() {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
        super.tearDown()
    }
    
    func doneUploads(masterVersion: MasterVersionInt, expectedNumberUploads:Int64) {
        let expectation = self.expectation(description: "doneUploads")

        ServerAPI.session.doneUploads(serverMasterVersion: masterVersion) {
            doneUploadsResult, error in
            
            XCTAssert(error == nil)
            if case .success(let numberUploads) = doneUploadsResult! {
                XCTAssert(numberUploads == expectedNumberUploads)
            }
            else {
                XCTFail()
            }
            
            expectation.fulfill()
        }
        
        waitForExpectations(timeout: 10.0, handler: nil)
    }
    
    func testDoneUploadsWorksWithOneFile() {
        let masterVersion = getMasterVersion()
        
        let fileUUID = UUID().uuidString
        
        let fileSize = uploadFile(fileName: "UploadMe", fileExtension: "txt", mimeType: "text/plain", fileUUID: fileUUID, serverMasterVersion: masterVersion)
        
        doneUploads(masterVersion: masterVersion, expectedNumberUploads: 1)
        
        getFileIndex(expectedFiles: [
            (fileUUID: fileUUID, fileSize: fileSize!)
        ])
    }
    
    func testDoneUploadsWorksWithTwoFiles() {
        let masterVersion = getMasterVersion()
        
        let fileUUID1 = UUID().uuidString
        let fileUUID2 = UUID().uuidString

        let fileSize1 = uploadFile(fileName: "UploadMe", fileExtension: "txt", mimeType: "text/plain", fileUUID: fileUUID1, serverMasterVersion: masterVersion)
        let fileSize2 = uploadFile(fileName: "Cat", fileExtension: "jpg", mimeType: "image/jpeg", fileUUID: fileUUID2, serverMasterVersion: masterVersion)
        
        doneUploads(masterVersion: masterVersion, expectedNumberUploads: 2)
        
        getFileIndex(expectedFiles: [
            (fileUUID: fileUUID1, fileSize: fileSize1!),
            (fileUUID: fileUUID2, fileSize: fileSize2!)
        ])
    }
    
    func testDoneUploadsConflict() {
        let masterVersion = getMasterVersion()
        
        let deviceUUID1 = Foundation.UUID()
        let deviceUUID2 = Foundation.UUID()

        deviceUUID = deviceUUID1
        _ = uploadFile(fileName: "UploadMe", fileExtension: "txt", mimeType: "text/plain", serverMasterVersion: masterVersion)
        
        deviceUUID = deviceUUID2
        _ = uploadFile(fileName: "UploadMe", fileExtension: "txt", mimeType: "text/plain", serverMasterVersion: masterVersion)
        
        let expectation1 = self.expectation(description: "doneUploads1")
        let expectation2 = self.expectation(description: "doneUploads2")
        
        var doneRequest1 = false
        
        deviceUUID = deviceUUID1 // for ServerAPIDelegate
        testLockSync = 5
        deviceUUIDCalled = false
        
        // A lock will be obtained by this first request.
        ServerAPI.session.doneUploads(serverMasterVersion: masterVersion) {
            doneUploadsResult, error in
            
            XCTAssert(error == nil)
            if case .success(let numberUploads) = doneUploadsResult! {
                XCTAssert(numberUploads == 1, "Number uploads = \(numberUploads)")
            }
            else {
                XCTFail()
            }
            
            Log.special("Finished doneUploads1")
            
            doneRequest1 = true
            expectation1.fulfill()
        }

        // Let above `doneUploads` request get started -- by delaying the 2nd request.
        TimedCallback.withDuration(1.0) {
        
            // The first request should have started, and obtained the lock. This second request will block until the first is done, because of the transactional implementation of the server.
            XCTAssert(self.deviceUUIDCalled)

            self.deviceUUID = deviceUUID2
            self.testLockSync = nil
            
            ServerAPI.session.doneUploads(serverMasterVersion: masterVersion) {
                doneUploadsResult, error in
                            
                XCTAssert(error == nil)
                if case .serverMasterVersionUpdate(_) = doneUploadsResult! {
                }
                else {
                    XCTFail()
                }
                
                Log.special("Finished doneUploads2")
                
                XCTAssert(doneRequest1)
                expectation2.fulfill()
            }
        }
        
        waitForExpectations(timeout: 30.0, handler: nil)
    }
    
    // TODO: *2* I would like a test where there are concurrent DoneUploads operations-- across two users. e.g., users A and B each upload a file, and then concurrently do DoneUpload operatons-- this should not result in a lock/blocking situation, even with the transactional support because InnoDB does row level locking. (I'm not sure how to support access within a single iOS app by two Google users.)
    // This should be pretty much exactly like the above test, except (a) it should not result in locking/blocking, and (b) it should use two users not 1.
}


