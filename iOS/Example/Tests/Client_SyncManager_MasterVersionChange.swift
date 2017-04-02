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

// Test cases where the master version changes midway through the upload or download and forces a restart of the upload or download.

class Client_SyncManager_MasterVersionChange: TestCase {
    
    override func setUp() {
        super.setUp()
        resetFileMetaData()
    }
    
    override func tearDown() {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
        super.tearDown()
    }
    
    private func deleteFile(file: ServerAPI.FileToDelete, masterVersion:MasterVersionInt, completion:@escaping ()->()) {

        ServerAPI.session.uploadDeletion(file: file, serverMasterVersion: masterVersion) { (result, error)  in
            XCTAssert(error == nil)
            guard case .success = result! else {
                XCTFail()
                return
            }
            
            ServerAPI.session.doneUploads(serverMasterVersion: masterVersion) { (result, error)  in
                XCTAssert(error == nil)
                
                guard case .success(let numberUploadsTransferred) = result! else {
                    XCTFail()
                    return
                }
                
                XCTAssert(numberUploadsTransferred == 1)
                
                completion()
            }
        }
    }
    
    private func fullUploadOfFile(url: URL, fileUUID:String, mimeType:String, completion:@escaping (_ masterVersion:MasterVersionInt)->()) {
        // Get the master version
        ServerAPI.session.fileIndex { (fileIndex, masterVersion, error) in
            XCTAssert(error == nil)
            XCTAssert(masterVersion! >= 0)
            
            let mimeType:String! = "text/plain"
            let file = ServerAPI.File(localURL: url, fileUUID: fileUUID, mimeType: mimeType, cloudFolderName: self.cloudFolderName, deviceUUID: self.deviceUUID.uuidString, appMetaData: nil, fileVersion: 0)
            
            ServerAPI.session.uploadFile(file: file, serverMasterVersion: masterVersion!) { uploadFileResult, error in
                XCTAssert(error == nil)

                guard case .success(_) = uploadFileResult! else {
                    XCTFail()
                    return
                }

                ServerAPI.session.doneUploads(serverMasterVersion: masterVersion!) {
                    doneUploadsResult, error in
                    
                    XCTAssert(error == nil)
                    
                    guard case .success(let numberUploads) = doneUploadsResult! else {
                        return
                    }
                    
                    XCTAssert(numberUploads == 1)
                    
                    completion(masterVersion!)
                }
            }
        }
    }
    
    // Demonstrate that we can "recover" from a master version change during upload. This "recovery" is really just the client side work necessary to deal with our lazy synchronization process.
    private func masterVersionChangeDuringUpload(withDeletion:Bool = false) {
        // How do we instantiate the "during" part of this? What I want to do is something like this:
        
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
        
        let syncServerSingleFileUploadCompletedExp = self.expectation(description: "syncServerSingleFileUploadCompleted")
        
        var shouldSaveDownloadsExp:XCTestExpectation?
        
        if !withDeletion {
            shouldSaveDownloadsExp = self.expectation(description: "shouldSaveDownloads")
        }
        
        var singleUploadsCompleted = 0
        
        syncServerEventOccurred = {event in
            switch event {
            case .syncDone:
                expectation1.fulfill()
                
            case .fileUploadsCompleted(numberOfFiles: let number):
                XCTAssert(number == 2)
                
                // This is three because one of the uploads is repeated when the master version is updated.
                XCTAssert(singleUploadsCompleted == 3, "Uploads actually completed: \(singleUploadsCompleted)")
                
                expectation2.fulfill()
                
            case .singleFileUploadComplete(_):
                singleUploadsCompleted += 1
                
            default:
                XCTFail()
            }
        }
    
        let previousSyncServerSingleFileUploadCompleted = self.syncServerSingleFileUploadCompleted
        
        if !withDeletion {
            shouldSaveDownloads = { downloads in
                XCTAssert(downloads.count == 1)
                shouldSaveDownloadsExp!.fulfill()
            }
        }
    
        syncServerSingleFileUploadCompleted = {next in
            // A single upload was completed. Let's upload another file by "another" client. This code is a little ugly because I can't kick off another `waitForExpectations`.
            
            // TODO: This is actually going to force a download by our client. What do we have to do here to accomodate that?
            
            // Note that the following code doesn't trigger `syncServerEventOccurred` because we're using the lower level interfaces.
 
            let previousDeviceUUID = self.deviceUUID
            
            // Use a different deviceUUID so that when we do a DoneUploads, we don't operate on the file uploads by the "other" client
            self.deviceUUID = UUID()
            
            let fileUUID = UUID().uuidString
            let fileURL = Bundle(for: ServerAPI_UploadFile.self).url(forResource: "UploadMe", withExtension: "txt")!
            
            self.fullUploadOfFile(url: fileURL, fileUUID: fileUUID, mimeType: "text/plain") { masterVersion in
                
                func end() {
                    self.deviceUUID = previousDeviceUUID
                    self.syncServerSingleFileUploadCompleted = previousSyncServerSingleFileUploadCompleted
                    syncServerSingleFileUploadCompletedExp.fulfill()
                    next()
                }
                
                if withDeletion {
                    let fileToDelete = ServerAPI.FileToDelete(fileUUID: fileUUID, fileVersion: 0)
                    self.deleteFile(file: fileToDelete, masterVersion: masterVersion + 1) {
                        end()
                    }
                }
                else {
                    end()
                }
            }
        }
        
        try! SyncServer.session.uploadImmutable(localFile: url, withAttributes: attr1)
        
        // The `syncServerEventSingleUploadCompleted` block above will get called after uploading a single file and bumps the master version, without the knowledge of the client. Which will cause a re-do of the already completed upload.
        // This tests getting the master version update on a file upload.
        
        try! SyncServer.session.uploadImmutable(localFile: url, withAttributes: attr2)
        SyncServer.session.sync()
        
        waitForExpectations(timeout: 20.0, handler: nil)
        
        getFileIndex(expectedFiles: [
            (fileUUID: fileUUID1, fileSize: nil),
            (fileUUID: fileUUID2, fileSize: nil)
        ])
        
        var masterVersion:MasterVersionInt!
        CoreData.sessionNamed(Constants.coreDataName).performAndWait() {
            masterVersion = Singleton.get().masterVersion
        }
        
        let file1 = ServerAPI.File(localURL: nil, fileUUID: fileUUID1, mimeType: nil, cloudFolderName: nil, deviceUUID: nil, appMetaData: nil, fileVersion: 0)
        onlyDownloadFile(comparisonFileURL: url as URL, file: file1, masterVersion: masterVersion)
        
        let file2 = ServerAPI.File(localURL: nil, fileUUID: fileUUID2, mimeType: nil, cloudFolderName: nil, deviceUUID: nil, appMetaData: nil, fileVersion: 0)
        onlyDownloadFile(comparisonFileURL: url as URL, file: file2, masterVersion: masterVersion)
    }
    
    func testMasterVersionChangeDuringUpload() {
        masterVersionChangeDuringUpload()
    }

    // Test case where the secondary client does an upload followed by an immediate deletion of that same file. No delegate methods will be called because the primary client never knew about the file in the first place.
    func testMasterVersionChangeDuringUploadWithDeletion() {
        masterVersionChangeDuringUpload(withDeletion:true)
    }
    
    // TODO: *0* First, using .sync(), upload a file. Then proceed as above, but the intervening "other" client does a deletion. So, this will cause a download deletion to interrupt the upload.
    func testMasterVersionChangeBecauseOfKnownFileDeletion() {
        let fileUUID1 = UUID().uuidString
        let fileUUID2 = UUID().uuidString

        let attr1 = SyncAttributes(fileUUID: fileUUID1, mimeType: "text/plain")
        let attr2 = SyncAttributes(fileUUID: fileUUID2, mimeType: "text/plain")

        let url = SMRelativeLocalURL(withRelativePath: "UploadMe2.txt", toBaseURLType: .mainBundle)!
    
        SyncServer.session.eventsDesired = [.syncDone, .fileUploadsCompleted]

        let syncDone1Exp = self.expectation(description: "syncDone1Exp")
        let file1Exp = self.expectation(description: "file1Exp")

        syncServerEventOccurred = {event in
            switch event {
            case .syncDone:
                syncDone1Exp.fulfill()
                
            case .fileUploadsCompleted(numberOfFiles: let number):
                XCTAssert(number == 1)
                file1Exp.fulfill()
                
            default:
                XCTFail()
            }
        }
        
        // 1) Do the upload of the first file.
        try! SyncServer.session.uploadImmutable(localFile: url, withAttributes: attr1)
        SyncServer.session.sync()
        
        waitForExpectations(timeout: 20.0, handler: nil)
        
        SyncServer.session.eventsDesired = [.syncDone, .fileUploadsCompleted, .singleFileUploadComplete]
        
        let syncDone2Exp = self.expectation(description: "syncDone2Exp")
        let fileUploadsCompletedExp = self.expectation(description: "fileUploadsCompleted")
        let syncServerSingleFileUploadCompletedExp = self.expectation(description: "syncServerSingleUploadCompleted")
        let shouldDoDeletionsExp = self.expectation(description: "shouldDoDeletionsExp")

        var singleUploadsCompleted = 0
        
        syncServerEventOccurred = {event in
            switch event {
            case .syncDone:
                syncDone2Exp.fulfill()
                
            case .fileUploadsCompleted(numberOfFiles: let number):
                XCTAssert(number == 1)
                XCTAssert(singleUploadsCompleted == 2, "Uploads actually completed: \(singleUploadsCompleted)")
                fileUploadsCompletedExp.fulfill()
                
            case .singleFileUploadComplete(_):
                singleUploadsCompleted += 1
                
            default:
                XCTFail()
            }
        }
        
        let previousShouldDoDeletions = shouldDoDeletions
        shouldDoDeletions = {deletions in
            XCTAssert(deletions.count == 1)
            self.shouldDoDeletions = previousShouldDoDeletions
            shouldDoDeletionsExp.fulfill()
        }
    
        let previousSyncServerSingleFileUploadCompleted = self.syncServerSingleFileUploadCompleted
    
        syncServerSingleFileUploadCompleted = {next in
            let previousDeviceUUID = self.deviceUUID
            self.deviceUUID = UUID()
            
            // Get the master version
            ServerAPI.session.fileIndex { (fileIndex, masterVersion, error) in
                XCTAssert(error == nil)
                XCTAssert(masterVersion! >= 0)
                
                let fileToDelete = ServerAPI.FileToDelete(fileUUID: fileUUID1, fileVersion: 0)
                self.deleteFile(file: fileToDelete, masterVersion: masterVersion!) {
                    self.deviceUUID = previousDeviceUUID
                    
                    self.syncServerSingleFileUploadCompleted = previousSyncServerSingleFileUploadCompleted
                    syncServerSingleFileUploadCompletedExp.fulfill()
                    next()
                }
            }
        }
        
        // 2) Do the upload of the second file, interrupted by the deletion of the first. This tests getting the master version update on DoneUploads.

        try! SyncServer.session.uploadImmutable(localFile: url, withAttributes: attr2)
        SyncServer.session.sync()
        
        waitForExpectations(timeout: 20.0, handler: nil)
        
        getFileIndex(expectedFiles: [
            (fileUUID: fileUUID2, fileSize: nil),
        ])
        
        var masterVersion:MasterVersionInt!
        CoreData.sessionNamed(Constants.coreDataName).performAndWait {
            masterVersion = Singleton.get().masterVersion
        }
        
        let file2 = ServerAPI.File(localURL: nil, fileUUID: fileUUID2, mimeType: nil, cloudFolderName: nil, deviceUUID: nil, appMetaData: nil, fileVersion: 0)
        onlyDownloadFile(comparisonFileURL: url as URL, file: file2, masterVersion: masterVersion)
    }
    
    // Test getting a master version update an UploadDeletion
    func testMasterVersionUpdateOnUploadDeletion() {
        let url = SMRelativeLocalURL(withRelativePath: "UploadMe2.txt", toBaseURLType: .mainBundle)!
        let fileUUID1 = UUID().uuidString
        let attr1 = SyncAttributes(fileUUID: fileUUID1, mimeType: "text/plain")

        // 1) Preparation: Upload a file, identified by UUID1. This is the file we'll delete below. We have to use the SyncServer.session client interface so that it will get recorded in the local meta data for the client.

        SyncServer.session.eventsDesired = [.syncDone]

        let syncDoneExp1 = self.expectation(description: "syncDoneExp1")
        
        var singleUploadsCompleted = 0
        
        syncServerEventOccurred = {event in
            switch event {
            case .syncDone:
                syncDoneExp1.fulfill()
                
            default:
                XCTFail("\(event)")
            }
        }
        
        try! SyncServer.session.uploadImmutable(localFile: url, withAttributes: attr1)
        SyncServer.session.sync()

        waitForExpectations(timeout: 20.0, handler: nil)

        // This file will trigger the master version update
        let fileUUID2 = UUID().uuidString
        
        // File to upload which will cause a SyncServer event which will allow us to upload fileUUID2
        let fileUUID3 = UUID().uuidString
        
        let attr3 = SyncAttributes(fileUUID: fileUUID3, mimeType: "text/plain")

        SyncServer.session.eventsDesired = [.syncDone, .fileUploadsCompleted, .singleFileUploadComplete, .uploadDeletionsCompleted]
        
        let syncDoneExp2 = self.expectation(description: "syncDoneExp2")
        let syncServerSingleUploadCompletedExp = self.expectation(description: "syncServerSingleUploadCompletedExp")
        let shouldSaveDownloadsExp = self.expectation(description: "shouldSaveDownloadsExp")
        let fileUploadsCompletedExp = self.expectation(description: "fileUploadsCompletedExp")
        let uploadDeletionsCompletedExp = self.expectation(description: "uploadDeletionsCompletedExp")
                
        syncServerEventOccurred = {event in
            switch event {
            case .syncDone:
                syncDoneExp2.fulfill()

            case .fileUploadsCompleted(numberOfFiles: let number):
                XCTAssert(number == 1)
                
                // This is two because the upload is repeated when the master version is updated.
                XCTAssert(singleUploadsCompleted == 2, "Uploads actually completed: \(singleUploadsCompleted)")
                
                fileUploadsCompletedExp.fulfill()
                
            case .uploadDeletionsCompleted(numberOfFiles: let number):
                XCTAssert(number == 1)
                uploadDeletionsCompletedExp.fulfill()
                
            case .singleFileUploadComplete(_):
                singleUploadsCompleted += 1
                
            default:
                XCTFail()
            }
        }
        
        shouldSaveDownloads = { downloads in
            XCTAssert(downloads.count == 1)
            shouldSaveDownloadsExp.fulfill()
        }
    
        let previousSyncSingleFileUploadCompleted = self.syncServerSingleFileUploadCompleted

        syncServerSingleFileUploadCompleted = { next in
            // Simulate the Upload of fileUUID2 as a different device
            let previousDeviceUUID = self.deviceUUID
            self.deviceUUID = UUID()
            
            self.fullUploadOfFile(url: url as URL, fileUUID: fileUUID2, mimeType: "text/plain") { masterVersion in
            
                self.deviceUUID = previousDeviceUUID
                syncServerSingleUploadCompletedExp.fulfill()
                self.syncServerSingleFileUploadCompleted = previousSyncSingleFileUploadCompleted
                next()
            }
        }
        
        do {
            try SyncServer.session.uploadImmutable(localFile: url, withAttributes: attr3)
            try SyncServer.session.delete(fileWithUUID: fileUUID1)
        } catch (let error) {
            XCTFail("\(error)")
        }
        
        SyncServer.session.sync()
        
        waitForExpectations(timeout: 20.0, handler: nil)
    }
    
    func testMasterVersionChangeDuringDownload() {
        // Algorithm:
        // Upload two files *not* using the client upload.
        // Next, use the client interface to sync files.
        // When a single file has been downloaded, upload another file (*not* using the client upload)
        // This should trigger the master version update.
        
        let masterVersion = getMasterVersion()
        
        let fileUUID1 = UUID().uuidString
        let fileUUID2 = UUID().uuidString

        let fileURL = Bundle(for: ServerAPI_UploadFile.self).url(forResource: "UploadMe", withExtension: "txt")!
        
        guard let (_, _) = uploadFile(fileURL:fileURL, mimeType: "text/plain", fileUUID: fileUUID1, serverMasterVersion: masterVersion) else {
            XCTFail()
            return
        }
        
        guard let (_, _) = uploadFile(fileURL:fileURL, mimeType: "text/plain", fileUUID: fileUUID2, serverMasterVersion: masterVersion) else {
            XCTFail()
            return
        }
        
        doneUploads(masterVersion: masterVersion, expectedNumberUploads: 2)
        
        SyncServer.session.eventsDesired = [.syncDone, .fileDownloadsCompleted, .singleFileDownloadComplete]
        
        let syncDoneExp = self.expectation(description: "syncDoneExp")
        let syncServerSingleFileDownloadCompletedExp = self.expectation(description: "syncServerSingleFileDownloadCompletedExp")
        let shouldSaveDownloadsExp = self.expectation(description: "shouldSaveDownloadsExp")
        let fileDownloadsCompletedExp = self.expectation(description: "fileDownloadsCompletedExp")
        
        var singleDownloadCount = 0
        
        syncServerEventOccurred = {event in
            switch event {
            case .syncDone:
                syncDoneExp.fulfill()

            case .fileDownloadsCompleted(numberOfFiles: let number):
                XCTAssert(number == 3)
                
                XCTAssert(singleDownloadCount == 4, "Downloads actually completed: \(singleDownloadCount)")
                
                fileDownloadsCompletedExp.fulfill()
                
            case .singleFileDownloadComplete(_):
                singleDownloadCount += 1
                
            default:
                XCTFail()
            }
        }
        
        shouldSaveDownloads = { downloads in
            // In the end, the call to `shouldSaveDownloads` should be for 3 files: The two initially uploaded, and the third uploaded after the first download. The master version update will then cause all three to then be downloaded.
            XCTAssert(downloads.count == 3)
            
            shouldSaveDownloadsExp.fulfill()
        }
    
        let previousSyncSingleFileDownloadCompleted = self.syncServerSingleFileDownloadCompleted

        let fileUUID3 = UUID().uuidString

        syncServerSingleFileDownloadCompleted = { next in
            // Simulate the Upload of fileUUID3 as a different device
            let previousDeviceUUID = self.deviceUUID
            self.deviceUUID = UUID()
            
            self.fullUploadOfFile(url: fileURL, fileUUID: fileUUID3, mimeType: "text/plain") { masterVersion in
            
                self.deviceUUID = previousDeviceUUID
                syncServerSingleFileDownloadCompletedExp.fulfill()
                self.syncServerSingleFileDownloadCompleted = previousSyncSingleFileDownloadCompleted
                next()
            }
        }
        
        SyncServer.session.sync()
        
        waitForExpectations(timeout: 20.0, handler: nil)
    }
}
