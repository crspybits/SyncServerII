//
//  ServerAPI_DownloadFile.swift
//  SyncServer
//
//  Created by Christopher Prince on 2/12/17.
//  Copyright © 2017 Spastic Muffin, LLC. All rights reserved.
//

import XCTest
@testable import SyncServer

class ServerAPI_DownloadFile: TestCase {
    
    override func setUp() {
        super.setUp()
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }
    
    override func tearDown() {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
        super.tearDown()
    }
    
    func downloadTextFile(appMetaData:String? = nil) {
        let masterVersion = getMasterVersion()
        
        let fileUUID = UUID().uuidString
        
        let uploadFileURL = Bundle(for: ServerAPI_DownloadFile.self).url(forResource: "UploadMe", withExtension: "txt")
        XCTAssert(uploadFileURL != nil)
        
        guard let (fileSize, file) = uploadFile(fileName: "UploadMe", fileExtension: "txt", mimeType: "text/plain", fileUUID: fileUUID, serverMasterVersion: masterVersion, appMetaData:appMetaData) else {
            return
        }
        
        doneUploads(masterVersion: masterVersion, expectedNumberUploads: 1)
        
        let expectation = self.expectation(description: "doneUploads")

        ServerAPI.session.downloadFile(file: file, serverMasterVersion: masterVersion + 1) { (result, error) in
        
            XCTAssert(error == nil)
            XCTAssert(result != nil)
            
            if case .success(let downloadedFile) = result! {
                XCTAssert(FilesMisc.compareFiles(file1: uploadFileURL!, file2: downloadedFile.url as URL))
                XCTAssert(downloadedFile.appMetaData == appMetaData)
                XCTAssert(fileSize == downloadedFile.fileSizeBytes)
            }
            else {
                XCTFail()
            }
            
            expectation.fulfill()
        }
        
        waitForExpectations(timeout: 10.0, handler: nil)
    }
    
    func testDownloadTextFile() {
        downloadTextFile()
    }
    
    func testDownloadTextFileWithAppMetaData() {
        downloadTextFile(appMetaData: "foobar was here")
    }
    
    // TODO: *1* Test that two concurrent downloads work.
}
