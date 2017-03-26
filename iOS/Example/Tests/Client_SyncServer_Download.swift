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
        super.setUp()
        DownloadFileTracker.removeAll()
        DirectoryEntry.removeAll()
        UploadFileTracker.removeAll()
        UploadQueue.removeAll()
        UploadQueues.removeAll()
        
        CoreData.sessionNamed(Constants.coreDataName).saveContext()

        removeAllServerFilesInFileIndex()
    }
    
    override func tearDown() {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
        super.tearDown()
    }
    
    // TODO: *1* Other download test cases using .sync()
    
    func testDownloadByDifferentDeviceUUIDThanUpload() {
        let initialDeviceUUID = self.deviceUUID

        // First upload a file.
        let masterVersion = getMasterVersion()
        
        let fileUUID = UUID().uuidString
        let fileURL = Bundle(for: ServerAPI_UploadFile.self).url(forResource: "UploadMe", withExtension: "txt")!
        
        guard let (_, _) = uploadFile(fileURL:fileURL, mimeType: "text/plain", fileUUID: fileUUID, serverMasterVersion: masterVersion) else {
            return
        }
        
        doneUploads(masterVersion: masterVersion, expectedNumberUploads: 1)
        
        let expectation = self.expectation(description: "test1")
        self.deviceUUID = Foundation.UUID()
        
        shouldSaveDownloads = { downloads in
            expectation.fulfill()
        }
        
        // Next, initiate the download using .sync()
        SyncServer.session.sync()
        
        XCTAssert(initialDeviceUUID != ServerAPI.session.delegate.deviceUUID(forServerAPI: ServerAPI.session))
        
        waitForExpectations(timeout: 30.0, handler: nil)
    }    
}
