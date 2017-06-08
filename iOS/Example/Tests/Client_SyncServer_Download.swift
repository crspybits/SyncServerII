//
//  Client_SyncServer_Download.swift
//  SyncServer
//
//  Created by Christopher Prince on 3/22/17.
//  Copyright © 2017 CocoaPods. All rights reserved.
//

import XCTest
@testable import SyncServer
import SMCoreLib
import Foundation

class Client_SyncServer_Download: TestCase {
    
    override func setUp() {
        super.setUp()
        resetFileMetaData()
    }
    
    override func tearDown() {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
        super.tearDown()
    }
    
    // TODO: *1* Other download test cases using .sync()
    
    func testDownloadByDifferentDeviceUUIDThanUpload() {
         doASingleDownloadUsingSync(fileName: "UploadMe", fileExtension:"txt", mimeType: "text/plain")
    }
    
    func testDownloadTwoFilesBackToBack() {
        let initialDeviceUUID = self.deviceUUID

        // First upload two files.
        let masterVersion = getMasterVersion()
        
        let fileUUID1 = UUID().uuidString
        let fileUUID2 = UUID().uuidString

        let fileURL = Bundle(for: ServerAPI_UploadFile.self).url(forResource: "UploadMe", withExtension: "txt")!
        
        guard let (_, _) = uploadFile(fileURL:fileURL, mimeType: "text/plain", fileUUID: fileUUID1, serverMasterVersion: masterVersion) else {
            return
        }
        
        guard let (_, _) = uploadFile(fileURL:fileURL, mimeType: "text/plain", fileUUID: fileUUID2, serverMasterVersion: masterVersion) else {
            return
        }
        
        doneUploads(masterVersion: masterVersion, expectedNumberUploads: 2)
        
        let expectation = self.expectation(description: "test1")
        self.deviceUUID = Foundation.UUID()
        
        shouldSaveDownloads = { downloads in
            XCTAssert(downloads.count == 2)
            expectation.fulfill()
        }
        
        // Next, initiate the download using .sync()
        SyncServer.session.sync()
        
        XCTAssert(initialDeviceUUID != ServerAPI.session.delegate.deviceUUID(forServerAPI: ServerAPI.session))
        
        waitForExpectations(timeout: 30.0, handler: nil)
    }
    
    func testDownloadWithMetaData() {
         doASingleDownloadUsingSync(fileName: "UploadMe", fileExtension:"txt", mimeType: "text/plain", appMetaData: "Some app meta data")
    }
}
