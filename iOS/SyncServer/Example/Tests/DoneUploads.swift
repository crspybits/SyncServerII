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
        let apiDelegate = ServerAPIDelegateObject()
        ServerAPI.session.delegate = self
        
        let masterVersion = getMasterVersion()
        
        let deviceUUID1 = Foundation.UUID()
        let deviceUUID2 = Foundation.UUID()

        apiDelegate.deviceUUID = deviceUUID1
        _ = uploadFile(fileName: "UploadMe", fileExtension: "txt", mimeType: "text/plain", serverMasterVersion: masterVersion)
        
        apiDelegate.deviceUUID = deviceUUID2
        _ = uploadFile(fileName: "UploadMe", fileExtension: "txt", mimeType: "text/plain", serverMasterVersion: masterVersion)
        
        let expectation1 = self.expectation(description: "doneUploads1")
        let expectation2 = self.expectation(description: "doneUploads2")
        
        var doneRequest1 = false
        
        apiDelegate.deviceUUID = deviceUUID1 // for ServerAPIDelegate
        apiDelegate.testLockSync = 5
        apiDelegate.deviceUUIDCalled = false
        
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

        // Let above `doneUploads` request get started -- by putting the second request on a background thread.
        DispatchQueue.global(qos: .background).async {
            // The first request should have started
            XCTAssert(apiDelegate.deviceUUIDCalled)

            apiDelegate.deviceUUID = deviceUUID2
            apiDelegate.testLockSync = nil
            
            ServerAPI.session.doneUploads(serverMasterVersion: masterVersion) {
                doneUploadsResult, error in
                            
                XCTAssert(error == nil)
                if case .serverMasterVersionUpdate(let masterVersionUpdate) = doneUploadsResult! {
                    XCTAssert(masterVersionUpdate == masterVersion + 1)
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
}

class ServerAPIDelegateObject : ServerAPIDelegate {
    var deviceUUID: Foundation.UUID!
    var testLockSync: TimeInterval?
    var deviceUUIDCalled:Bool = false
    var testLockSyncCalled:Bool = false
    
    func deviceUUID(forServerAPI: ServerAPI) -> Foundation.UUID {
        deviceUUIDCalled = true
        return deviceUUID
    }
    
    func doneUploadsRequestTestLockSync() -> TimeInterval? {
        testLockSyncCalled = true
        return testLockSync
    }
}

