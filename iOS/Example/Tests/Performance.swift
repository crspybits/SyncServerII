//
//  Performance.swift
//  SyncServer
//
//  Created by Christopher Prince on 5/21/17.
//  Copyright © 2017 CocoaPods. All rights reserved.
//

import XCTest
@testable import SyncServer

class Performance: TestCase {
    
    override func setUp() {
        super.setUp()
        resetFileMetaData(removeServerFiles: true, actualDeletion: false)
    }
    
    override func tearDown() {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
        super.tearDown()
    }
    
    func downloadNFiles(_ N:UInt) {
        // First upload N files.
        let masterVersion = getMasterVersion()
        let fileURL = Bundle(for: ServerAPI_UploadFile.self).url(forResource: "Cat", withExtension: "jpg")!
        
        for _ in 1...N {
            let fileUUID = UUID().uuidString

            guard let (_, _) = uploadFile(fileURL:fileURL, mimeType: "image/jpeg", fileUUID: fileUUID, serverMasterVersion: masterVersion) else {
                return
            }
        }
        
        doneUploads(masterVersion: masterVersion, expectedNumberUploads: Int64(N))
        
        let expectation = self.expectation(description: "downloadNFiles")
        self.deviceUUID = Foundation.UUID()
        
        shouldSaveDownloads = { downloads in
            XCTAssert(downloads.count == Int(N), "Number of downloads were: \(downloads.count)")
            expectation.fulfill()
        }
        
        // Next, initiate the download using .sync()
        SyncServer.session.sync()
        
        waitForExpectations(timeout: Double(N) * 20.0, handler: nil)
    }
    
    func test10Downloads() {
        downloadNFiles(10)
    }
    
    // TODO: *0* Delete 50 files in the same done uploads.
}
