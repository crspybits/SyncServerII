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
    
    func testDownloadTextFile() {
        uploadAndDownloadTextFile()
    }
    
    func testDownloadTextFileWithAppMetaData() {
        uploadAndDownloadTextFile(appMetaData: "foobar was here")
    }
    
    func testThatParallelDownloadsWork() {
        let masterVersion = getMasterVersion()

        let fileURL = Bundle(for: ServerAPI_UploadFile.self).url(forResource: "Cat", withExtension: "jpg")!
        let (_, file1) = uploadFile(fileURL:fileURL, mimeType: "image/jpeg", serverMasterVersion: masterVersion)!
        let (_, file2) = uploadFile(fileURL:fileURL, mimeType: "image/jpeg", serverMasterVersion: masterVersion)!
        
        doneUploads(masterVersion: masterVersion, expectedNumberUploads: 2)

        let expectation1 = self.expectation(description: "downloadFile1")
        let expectation2 = self.expectation(description: "downloadFile2")

        ServerAPI.session.downloadFile(file: file1, serverMasterVersion: masterVersion + 1) { (result, error) in
        
            XCTAssert(error == nil)
            XCTAssert(result != nil)
            
            if case .success(let downloadedFile) = result! {
                XCTAssert(FilesMisc.compareFiles(file1: fileURL, file2: downloadedFile.url as URL))
            }
            else {
                XCTFail()
            }
            
            expectation1.fulfill()
        }
        
        ServerAPI.session.downloadFile(file: file2, serverMasterVersion: masterVersion + 1) { (result, error) in
        
            XCTAssert(error == nil)
            XCTAssert(result != nil)
            
            if case .success(let downloadedFile) = result! {
                XCTAssert(FilesMisc.compareFiles(file1: fileURL, file2: downloadedFile.url as URL))
            }
            else {
                XCTFail()
            }
            
            expectation2.fulfill()
        }
        
        waitForExpectations(timeout: 120.0, handler: nil)
    }
    
    // TODO: *1* Also try parallel downloads from different (simulated) deviceUUID's.
}
