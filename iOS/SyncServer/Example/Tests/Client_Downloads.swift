//
//  Client_Downloads.swift
//  SyncServer
//
//  Created by Christopher Prince on 2/23/17.
//  Copyright © 2017 CocoaPods. All rights reserved.
//

import XCTest
@testable import SyncServer
import SMCoreLib

class Client_Downloads: TestCase {
    
    override func setUp() {
        super.setUp()
        DownloadFileTracker.removeAll()
        DirectoryEntry.removeAll()
        removeAllServerFiles()
    }
    
    override func tearDown() {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
        super.tearDown()
    }
    
    func testCheckForDownloadsWorks() {
        let masterVersion = getMasterVersion()
        
        let fileUUID = UUID().uuidString
        
        guard let (_, file) = uploadFile(fileName: "UploadMe", fileExtension: "txt", mimeType: "text/plain", fileUUID: fileUUID, serverMasterVersion: masterVersion) else {
            return
        }
        
        doneUploads(masterVersion: masterVersion, expectedNumberUploads: 1)
        
        let expectation = self.expectation(description: "check")

        // Make sure that checking for downloads shows this file is available for download, and appropriate Core Data objects are created.
        Download.session.check() { error in
            XCTAssert(error == nil)
            
            do {
                let dfts = try CoreData.sessionNamed(Constants.coreDataName).fetchAllObjects(withEntityName: DownloadFileTracker.entityName()) as? [DownloadFileTracker]
                XCTAssert(dfts!.count == 1)
                XCTAssert(dfts![0].fileUUID == fileUUID)
                XCTAssert(dfts![0].fileVersion == file.fileVersion)
                
                XCTAssert(MasterVersion.get().version == masterVersion + 1)
                
                let entries = try CoreData.sessionNamed(Constants.coreDataName).fetchAllObjects(withEntityName: DirectoryEntry.entityName()) as? [DirectoryEntry]
                XCTAssert(entries!.count == 1)
                XCTAssert(entries![0].fileUUID == fileUUID)
                XCTAssert(entries![0].fileVersion == file.fileVersion)
            } catch {
                XCTAssert(false)
            }
            
            expectation.fulfill()
        }
        
        waitForExpectations(timeout: 30.0, handler: nil)
    }

/*
    func testDownload() {
        let masterVersion = getMasterVersion()
        
        let fileUUID = UUID().uuidString
        
        guard let (fileSize, file) = uploadFile(fileName: "UploadMe", fileExtension: "txt", mimeType: "text/plain", fileUUID: fileUUID, serverMasterVersion: masterVersion) else {
            return
        }
        
        doneUploads(masterVersion: masterVersion, expectedNumberUploads: 1)
        
        // We've manually uploaded a file: Our local directory doesn't know about it. Next: trigger a client-level download.

    }
*/
}
