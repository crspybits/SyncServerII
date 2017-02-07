//
//  UploadFile.swift
//  SyncServer
//
//  Created by Christopher Prince on 2/4/17.
//  Copyright © 2017 CocoaPods. All rights reserved.
//

import XCTest
@testable import SyncServer

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
        _ = uploadFile(fileName: "UploadMe", fileExtension: "txt", mimeType: "text/plain", serverMasterVersion: masterVersion)
    }
    
    func testUploadJPEGFile() {
        let masterVersion = getMasterVersion()
        _ = uploadFile(fileName: "Cat", fileExtension: "jpg", mimeType: "image/jpeg", serverMasterVersion: masterVersion)
    }
    
    func testUploadTextFileWithNoAuthFails() {
        ServerNetworking.session.authenticationDelegate = nil
        _ = uploadFile(fileName: "UploadMe", fileExtension: "txt", mimeType: "text/plain", expectError: true)
    }
    
    func testUploadTwoFilesWithSameUUIDFails() {
        let masterVersion = getMasterVersion()
        let fileUUID = UUID().uuidString

        _ = uploadFile(fileName: "UploadMe", fileExtension: "txt", mimeType: "text/plain", fileUUID: fileUUID, serverMasterVersion: masterVersion)
        _ = uploadFile(fileName: "UploadMe", fileExtension: "txt", mimeType: "text/plain", fileUUID: fileUUID, serverMasterVersion: masterVersion, expectError: true)
    }
}
