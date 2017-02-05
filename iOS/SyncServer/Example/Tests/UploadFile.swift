//
//  UploadFile.swift
//  SyncServer
//
//  Created by Christopher Prince on 2/4/17.
//  Copyright © 2017 CocoaPods. All rights reserved.
//

import XCTest
@testable import SyncServer

class UploadFile: TestCase {
    let cloudFolderName = "Test.Folder"

    override func setUp() {
        super.setUp()
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }
    
    override func tearDown() {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
        super.tearDown()
    }
    
    func uploadFile(fileName:String, fileExtension:String, mimeType:String, expectError:Bool = false) {
        let fileURL = Bundle(for: UploadFile.self).url(forResource: fileName, withExtension: fileExtension)!
        let fileUUID = UUID().uuidString
        let deviceUUID = UUID().uuidString

        let file = ServerAPI.File(localURL: fileURL, fileUUID: fileUUID, mimeType: mimeType, cloudFolderName: cloudFolderName, deviceUUID: deviceUUID, appMetaData: nil, fileVersion: 0)
        
        // Just to get the size-- this is redundant with the file read in ServerAPI.session.uploadFile
        guard let fileData = try? Data(contentsOf: file.localURL) else {
            XCTFail()
            return
        }
        
        let expectation = self.expectation(description: "upload")

        ServerAPI.session.uploadFile(file: file, serverMasterVersion: 0) { uploadFileResult, error in
            if expectError {
                XCTAssert(error != nil)
            }
            else {
                XCTAssert(error == nil)
                if case .success(let size) = uploadFileResult! {
                    XCTAssert(Int64(fileData.count) == size)
                }
                else {
                    XCTFail()
                }
            }
            
            expectation.fulfill()
        }
        
        waitForExpectations(timeout: 30.0, handler: nil)
    }
    
    func testUploadTextFile() {
        uploadFile(fileName: "UploadMe", fileExtension: "txt", mimeType: "text/plain")
    }
    
    func testUploadJPEGFile() {
        uploadFile(fileName: "Cat", fileExtension: "jpg", mimeType: "image/jpeg")
    }
    
    func testUploadTextFileWithNoAuthFails() {
        ServerNetworking.session.authenticationDelegate = nil
        uploadFile(fileName: "UploadMe", fileExtension: "txt", mimeType: "text/plain", expectError: true)
    }
}
