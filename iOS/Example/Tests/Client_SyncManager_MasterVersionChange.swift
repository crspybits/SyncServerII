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

    // TODO: *0* Test cases where the master version changes midway through the upload or download and forces a restart of the upload or download.
    
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
        
        let syncServerEventSingleUploadCompletedExp = self.expectation(description: "syncServerEventSingleUploadCompleted")
        
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
    
        let previousSyncServerEventSingleUploadCompleted = self.syncServerEventSingleUploadCompleted
        
        if !withDeletion {
            shouldSaveDownloads = { downloads in
                XCTAssert(downloads.count == 1)
                shouldSaveDownloadsExp!.fulfill()
            }
        }
    
        syncServerEventSingleUploadCompleted = {next in
            // A single upload was completed. Let's upload another file by "another" client. This code is a little ugly because I can't kick off another `waitForExpectations`.
            
            // TODO: This is actually going to force a download by our client. What do we have to do here to accomodate that?
            
            // Note that the following code doesn't trigger `syncServerEventOccurred` because we're using the lower level interfaces.
 
            let previousDeviceUUID = self.deviceUUID
            
            // Use a different deviceUUID so that when we do a DoneUploads, we don't operate on the file uploads by the "other" client
            self.deviceUUID = UUID()
            
            let fileUUID = UUID().uuidString
            let fileURL = Bundle(for: ServerAPI_UploadFile.self).url(forResource: "UploadMe", withExtension: "txt")!
            
            // Get the master version
            ServerAPI.session.fileIndex { (fileIndex, masterVersion, error) in
                XCTAssert(error == nil)
                XCTAssert(masterVersion! >= 0)
                
                let mimeType:String! = "text/plain"
                let file = ServerAPI.File(localURL: fileURL, fileUUID: fileUUID, mimeType: mimeType, cloudFolderName: self.cloudFolderName, deviceUUID: self.deviceUUID.uuidString, appMetaData: nil, fileVersion: 0)
                
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
                        
                        func end() {
                            self.deviceUUID = previousDeviceUUID
                            
                            self.syncServerEventSingleUploadCompleted = previousSyncServerEventSingleUploadCompleted
                            syncServerEventSingleUploadCompletedExp.fulfill()
                            next()
                        }
                        
                        if withDeletion {
                            let fileToDelete = ServerAPI.FileToDelete(fileUUID: fileUUID, fileVersion: 0)
                            self.deleteFile(file: fileToDelete, masterVersion: masterVersion! + 1) {
                                end()
                            }
                        }
                        else {
                            end()
                        }
                    }
                }
            }
        }
        
        try! SyncServer.session.uploadImmutable(localFile: url, withAttributes: attr1)
        
        // The `syncServerEventSingleUploadCompleted` block above will get called after uploading a single file and bumps the master version, without the knowledge of the client. Which will cause a re-do of the already completed upload.
        
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
    
    func testMasterVersionChangeDuringUpload() {
        masterVersionChangeDuringUpload()
    }

    // Test case where the secondary client does an upload followed by an immediate deletion of that same file. No delegate methods will be called because the primary client never knew about the file in the first place.
    func testMasterVersionChangeDuringUploadWithDeletion() {
        masterVersionChangeDuringUpload(withDeletion:true)
    }
    
    // TODO: *0*
    /*
    func testMasterVersionChangeDuringDownload() {
    }
    */
}
