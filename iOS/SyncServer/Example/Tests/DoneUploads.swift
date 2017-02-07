//
//  DoneUploads.swift
//  SyncServer
//
//  Created by Christopher Prince on 1/31/17.
//  Copyright © 2017 CocoaPods. All rights reserved.
//

import XCTest
@testable import SyncServer

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
    
    // TODO: Move `testLockOnDoneUploadsWorks` from server tests to here.
}

