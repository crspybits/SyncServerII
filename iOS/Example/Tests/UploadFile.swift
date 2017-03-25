//
//  UploadFile.swift
//  SyncServer
//
//  Created by Christopher Prince on 2/4/17.
//  Copyright © 2017 Spastic Muffin, LLC. All rights reserved.
//

import XCTest
@testable import SyncServer
import SMCoreLib

class ServerAPI_UploadFile: TestCase {
    
    override func setUp() {
        super.setUp()
    }
    
    override func tearDown() {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
        super.tearDown()
    }
    
    func testUploadTextFile() {
        let masterVersion = getMasterVersion()
        let fileURL = Bundle(for: ServerAPI_UploadFile.self).url(forResource: "UploadMe", withExtension: "txt")!
        _ = uploadFile(fileURL:fileURL, mimeType: "text/plain", serverMasterVersion: masterVersion)
    }
    
    func testUploadJPEGFile() {
        let masterVersion = getMasterVersion()
        let fileURL = Bundle(for: ServerAPI_UploadFile.self).url(forResource: "Cat", withExtension: "jpg")!
        _ = uploadFile(fileURL:fileURL, mimeType: "image/jpeg", serverMasterVersion: masterVersion)
    }
    
    func testUploadTextFileWithNoAuthFails() {
        ServerNetworking.session.authenticationDelegate = nil
        let fileURL = Bundle(for: ServerAPI_UploadFile.self).url(forResource: "UploadMe", withExtension: "txt")!
        _ = uploadFile(fileURL:fileURL, mimeType: "text/plain", expectError: true)
    }
    
    // This should not fail because the second attempt doesn't add a second upload deletion-- the second attempt is to allow for recovery/retries.
    func testUploadTwoFilesWithSameUUIDFails() {
        let masterVersion = getMasterVersion()
        let fileUUID = UUID().uuidString
        let fileURL = Bundle(for: ServerAPI_UploadFile.self).url(forResource: "UploadMe", withExtension: "txt")!
        
        _ = uploadFile(fileURL:fileURL, mimeType: "text/plain", fileUUID: fileUUID, serverMasterVersion: masterVersion)
        
        _ = uploadFile(fileURL:fileURL, mimeType: "text/plain", fileUUID: fileUUID, serverMasterVersion: masterVersion)
    }
    
    func testParallelUploadsWork() {
        let masterVersion = getMasterVersion()

        let expectation1 = self.expectation(description: "upload1")
        let expectation2 = self.expectation(description: "upload2")
        let fileUUID1 = UUID().uuidString
        let fileUUID2 = UUID().uuidString
        Log.special("fileUUID1= \(fileUUID1); fileUUID2= \(fileUUID2)")
        
        _ = uploadFile(fileName: "UploadMe", fileExtension: "txt", mimeType: "text/plain", fileUUID:fileUUID1, serverMasterVersion: masterVersion, withExpectation:expectation1)
        
        _ = uploadFile(fileName: "UploadMe", fileExtension: "txt", mimeType: "text/plain", fileUUID:fileUUID2, serverMasterVersion: masterVersion, withExpectation:expectation2)

        waitForExpectations(timeout: 30.0, handler: nil)
    }
}
