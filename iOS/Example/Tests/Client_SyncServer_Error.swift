//
//  Client_SyncServer_Error.swift
//  SyncServer
//
//  Created by Christopher Prince on 4/2/17.
//  Copyright © 2017 Spastic Muffin, LLC. All rights reserved.
//

import XCTest
@testable import SyncServer
import SMCoreLib
import Foundation

class Client_SyncServer_Error: TestCase {
    override func setUp() {
        super.setUp()
        resetFileMetaData()
    }
    
    override func tearDown() {
        super.tearDown()
        ServerAPI.session.failEndpoints = false
    }
    
    func testSyncFailure() {
        ServerAPI.session.failEndpoints = true
        
        SyncServer.session.eventsDesired = []
        let errorExp = self.expectation(description: "errorExp")

        syncServerErrorOccurred = { error in
            errorExp.fulfill()
        }
        
        SyncServer.session.sync()
        
        waitForExpectations(timeout: 40.0, handler: nil)
    }
    
    func syncFailureAfterOtherClientUpload(retry:Bool = false) {
        let masterVersion = getMasterVersion()
        
        let fileUUID1 = UUID().uuidString

        let fileURL = Bundle(for: ServerAPI_UploadFile.self).url(forResource: "UploadMe", withExtension: "txt")!
        
        guard let (_, _) = uploadFile(fileURL:fileURL, mimeType: "text/plain", fileUUID: fileUUID1, serverMasterVersion: masterVersion) else {
            XCTFail()
            return
        }
        
        doneUploads(masterVersion: masterVersion, expectedNumberUploads: 1)
        
        ServerAPI.session.failEndpoints = true
        
        SyncServer.session.eventsDesired = []
        let errorExp = self.expectation(description: "errorExp1")

        syncServerErrorOccurred = { error in
            errorExp.fulfill()
        }
        
        SyncServer.session.sync()
        
        waitForExpectations(timeout: 40.0, handler: nil)
        
        if retry {
            ServerAPI.session.failEndpoints = false
            
            let syncDoneExp = self.expectation(description: "syncDoneExp")
            let shouldSaveDownloadsExp = self.expectation(description: "shouldSaveDownloadsExp")

            SyncServer.session.eventsDesired = [.syncDone]
        
            syncServerEventOccurred = { event in
                switch event {
                case .syncDone:
                    syncDoneExp.fulfill()
                    
                default:
                    XCTFail()
                }
            }
            
            shouldSaveDownloads = { downloads in
                XCTAssert(downloads.count == 1)
                shouldSaveDownloadsExp.fulfill()
            }
            
            SyncServer.session.sync()
            
            waitForExpectations(timeout: 10.0, handler: nil)
        }
    }
    
    func testSyncFailureAfterOtherClientUpload() {
        syncFailureAfterOtherClientUpload()
    }
    
    func testSyncFailureAfterOtherClientUploadWithRetry() {
        syncFailureAfterOtherClientUpload(retry:true)
    }
    
    private func failureAfterOneUpload(retry:Bool = false) {
        let url = SMRelativeLocalURL(withRelativePath: "UploadMe2.txt", toBaseURLType: .mainBundle)!
        let fileUUID1 = UUID().uuidString
        let fileUUID2 = UUID().uuidString

        let attr1 = SyncAttributes(fileUUID: fileUUID1, mimeType: "text/plain")
        let attr2 = SyncAttributes(fileUUID: fileUUID2, mimeType: "text/plain")
    
        let previousSyncServerSingleFileUploadCompleted = self.syncServerSingleFileUploadCompleted
    
        syncServerSingleFileUploadCompleted = {next in
            ServerAPI.session.failEndpoints = true

            self.syncServerSingleFileUploadCompleted = previousSyncServerSingleFileUploadCompleted
            next()
        }
        
        SyncServer.session.eventsDesired = []
        let errorExp = self.expectation(description: "errorExp1")

        syncServerErrorOccurred = { error in
            errorExp.fulfill()
        }
        
        try! SyncServer.session.uploadImmutable(localFile: url, withAttributes: attr1)
        try! SyncServer.session.uploadImmutable(localFile: url, withAttributes: attr2)
        SyncServer.session.sync()
        
        waitForExpectations(timeout: 50.0, handler: nil)

        if retry {
            ServerAPI.session.failEndpoints = false

            SyncServer.session.eventsDesired = [.syncDone, .fileUploadsCompleted, .singleFileUploadComplete]
            
            let syncDone = self.expectation(description: "syncDone")
            let fileUploadsCompletedExp = self.expectation(description: "fileUploadsCompletedExp")
            
            var singleUploadsCompleted = 0
            
            syncServerEventOccurred = {event in
                switch event {
                case .syncDone:
                    syncDone.fulfill()
                    
                case .fileUploadsCompleted(numberOfFiles: let number):
                    XCTAssert(number == 2)
                    
                    // One because only a single file needs to be uploaded the second time-- the first was uploaded before the error.
                    XCTAssert(singleUploadsCompleted == 1, "Uploads actually completed: \(singleUploadsCompleted)")
                    
                    fileUploadsCompletedExp.fulfill()
                    
                case .singleFileUploadComplete(_):
                    singleUploadsCompleted += 1
                    
                default:
                    XCTFail()
                }
            }
            
            SyncServer.session.sync()
            
            waitForExpectations(timeout: 20.0, handler: nil)
        }
    }
    
    func testFailureAfterOneUpload() {
        failureAfterOneUpload()
    }
    
    func testFailureAfterOneUploadWithRetry() {
        failureAfterOneUpload(retry:true)
    }
    
    private func failureAfterOneDownload(retry:Bool = false) {
        let fileUUID1 = UUID().uuidString
        let fileUUID2 = UUID().uuidString
        
        let masterVersion = getMasterVersion()
        
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
    
        let previousSyncServerSingleFileDownloadCompleted = self.syncServerSingleFileDownloadCompleted
    
        syncServerSingleFileDownloadCompleted = {next in
            ServerAPI.session.failEndpoints = true

            self.syncServerSingleFileDownloadCompleted = previousSyncServerSingleFileDownloadCompleted
            next()
        }
        
        SyncServer.session.eventsDesired = []
        let errorExp = self.expectation(description: "errorExp1")

        syncServerErrorOccurred = { error in
            errorExp.fulfill()
        }

        // 1) Get the download error.
        SyncServer.session.sync()
        waitForExpectations(timeout: 50.0, handler: nil)

        if retry {
            ServerAPI.session.failEndpoints = false

            SyncServer.session.eventsDesired = [.syncDone, .fileDownloadsCompleted, .singleFileDownloadComplete]
            
            let syncDone = self.expectation(description: "syncDone")
            let fileDownloadsCompletedExp = self.expectation(description: "fileDownloadsCompletedExp")
            let shouldSaveDownloadsExp = self.expectation(description: "shouldSaveDownloadsExp")

            var singleDownloadsCompleted = 0
            
            syncServerEventOccurred = {event in
                switch event {
                case .syncDone:
                    syncDone.fulfill()
                    
                case .fileDownloadsCompleted(numberOfFiles: let number):
                    XCTAssert(number == 2)
                    
                    // One because only a single file needs to be uploaded the second time-- the first was uploaded before the error.
                    XCTAssert(singleDownloadsCompleted == 1, "Uploads actually completed: \(singleDownloadsCompleted)")
                    
                    fileDownloadsCompletedExp.fulfill()
                    
                case .singleFileDownloadComplete(_):
                    singleDownloadsCompleted += 1
                    
                default:
                    XCTFail()
                }
            }
            
            shouldSaveDownloads = { downloads in
                XCTAssert(downloads.count == 2)
                shouldSaveDownloadsExp.fulfill()
            }
            
            SyncServer.session.sync()
            
            waitForExpectations(timeout: 20.0, handler: nil)
        }
    }
    
    func testFailureAfterOneDownload() {
        failureAfterOneDownload()
    }
    
    func testFailureAfterOneDownloadWithRetry() {
        failureAfterOneDownload(retry:true)
    } 
}
