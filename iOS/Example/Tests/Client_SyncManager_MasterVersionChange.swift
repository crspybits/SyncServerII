//
//  Client_SyncManager_MasterVersionChange.swift
//  SyncServer
//
//  Created by Christopher Prince on 3/3/17.
//  Copyright © 2017 Spastic Muffin, LLC. All rights reserved.
//

import XCTest
@testable import SyncServer
import SMCoreLib
import Foundation

class Client_SyncManager_MasterVersionChange: TestCase {
    
    override func setUp() {
        super.setUp()
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }
    
    override func tearDown() {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
        super.tearDown()
    }

#if false
    // TODO: *0* Test cases where the master version changes midway through the upload or download and forces a restart of the upload or download.
    
    // Demonstrate that we can "recover" from a master version change during upload. This "recovery" is really just the client side work necessary to deal with our lazy synchronization process.
    func testMasterVersionChangeDuringUpload() {
        // How do we instantiate the "during" part of this? What I want to do is to do is something like this:
        
        // try! SyncServer.session.uploadImmutable(localFile: url1, withAttributes: attr)
        // try! SyncServer.session.uploadImmutable(localFile: url2, withAttributes: attr)
        // SyncServer.session.sync()
        
        // Where between uploading files, some "other" client does an upload and sync, causing the masterVersion to update. We can use the ServerAPI directly and upload a file and do a DoneUploads.
        
        let url = SMRelativeLocalURL(withRelativePath: "UploadMe2.txt", toBaseURLType: .mainBundle)!
        let fileUUID1 = UUID().uuidString
        let fileUUID2 = UUID().uuidString

        let attr1 = SyncAttributes(fileUUID: fileUUID1, mimeType: "text/plain")
        let attr2 = SyncAttributes(fileUUID: fileUUID2, mimeType: "text/plain")

        SyncServer.session.eventsDesired = [.syncDone, .fileUploadsCompleted, .singleFileUploadComplete]
        let expectation1 = self.expectation(description: "test1")
        let expectation2 = self.expectation(description: "test2")
        
        var uploadsCompleted = 0
        
        syncServerEventOccurred = {event in
            switch event {
            case .syncDone:
                expectation1.fulfill()
                
            case .fileUploadsCompleted(numberOfFiles: let number):
                XCTAssert(number == 2)
                XCTAssert(uploadsCompleted == 2)
                expectation2.fulfill()
                
            case .singleFileUploadComplete(_):
                uploadsCompleted += 1
                
            default:
                XCTFail()
            }
        }
        
        syncServerEventSingleUploadCompleted = {next in
            // A single upload was completed. Let's upload another file by "another" client. 
            // TODO: This is actually going to force a download by our client. What do we have to do here to accomodate that?
            
            // Note that this block doesn't trigger `syncServerEventOccurred` because we're using the lower level interfaces.
            
            let masterVersion = self.getMasterVersion()
            
            let previousDeviceUUID = self.deviceUUID
            
            // Use a different deviceUUID so that when we do a DoneUploads, we don't operate on the file uploads by the "other" client
            self.deviceUUID = UUID()

            let fileUUID = UUID().uuidString
            let fileURL = Bundle(for: ServerAPI_UploadFile.self).url(forResource: "UploadMe", withExtension: "txt")!
            
            guard let (_, _) = self.uploadFile(fileURL:fileURL, mimeType: "text/plain", fileUUID: fileUUID, serverMasterVersion: masterVersion) else {
                next()
                XCTFail()
                return
            }
            
            self.doneUploads(masterVersion: masterVersion, expectedNumberUploads: 1)
            
            self.deviceUUID = previousDeviceUUID
            
            self.syncServerEventSingleUploadCompleted = nil
            next()
        }
        
        try! SyncServer.session.uploadImmutable(localFile: url, withAttributes: attr1)
        
        // The `syncServerEventSingleUploadCompleted` block above will get called here and bumps the master version, without the knowledge of the client.
        
        try! SyncServer.session.uploadImmutable(localFile: url, withAttributes: attr2)
        SyncServer.session.sync()
        
        waitForExpectations(timeout: 20.0, handler: nil)
        
        getFileIndex(expectedFiles: [
            (fileUUID: fileUUID1, fileSize: nil),
            (fileUUID: fileUUID2, fileSize: nil)
        ])
        
        let masterVersion = Singleton.get().masterVersion
        
        let file1 = ServerAPI.File(localURL: nil, fileUUID: fileUUID1, mimeType: nil, cloudFolderName: nil, deviceUUID: nil, appMetaData: nil, fileVersion: 0)
        onlyDownloadFile(comparisonFileURL: url as URL, file: file1, masterVersion: masterVersion)
        
        let file2 = ServerAPI.File(localURL: nil, fileUUID: fileUUID2, mimeType: nil, cloudFolderName: nil, deviceUUID: nil, appMetaData: nil, fileVersion: 0)
        onlyDownloadFile(comparisonFileURL: url as URL, file: file2, masterVersion: masterVersion)
    }
#endif

    // TODO: *0*
    // Test case where the secondary client does an upload followed by an immediate deletion of that same file. This is effectively a simpler case because no delegate methods need to be called because the primary client never knew about the file in the first place.
    
    // TODO: *0*
    func testMasterVersionChangeDuringDownload() {
    }
}
