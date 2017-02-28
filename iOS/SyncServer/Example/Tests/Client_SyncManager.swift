//
//  Client_SyncManager.swift
//  SyncServer
//
//  Created by Christopher Prince on 2/26/17.
//  Copyright © 2017 CocoaPods. All rights reserved.
//

import XCTest
@testable import SyncServer
import SMCoreLib

class Client_SyncManager: TestCase {
    var shouldSaveDownloads: ((_ downloads: [(downloadedFile: NSURL, downloadedFileAttributes: SyncAttributes)], _ next:()->()) -> ())!
    var syncServerEventOccurred: (SyncEvent) -> () = {event in }
    
    override func setUp() {
        super.setUp()
        
        DownloadFileTracker.removeAll()
        DirectoryEntry.removeAll()
        CoreData.sessionNamed(Constants.coreDataName).saveContext()
        
        SyncManager.session.delegate = self

        removeAllServerFilesInFileIndex()
    }
    
    override func tearDown() {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
        super.tearDown()
    }
    
    func testStartWithNoFilesOnServer() {
        let expectation = self.expectation(description: "next")

        SyncManager.session.start { (result, error) in
            XCTAssert(error == nil)
            guard case .noDownloadsAvailable = result! else {
                XCTFail()
                return
            }
            
            expectation.fulfill()
        }
        
        waitForExpectations(timeout: 30.0, handler: nil)
    }
    
    func testStartWithOneFileOnServer() {
        let masterVersion = getMasterVersion()
        
        let fileUUID = UUID().uuidString
        
        guard let (_, file) = uploadFile(fileName: "UploadMe", fileExtension: "txt", mimeType: "text/plain", fileUUID: fileUUID, serverMasterVersion: masterVersion) else {
            return
        }
        
        doneUploads(masterVersion: masterVersion, expectedNumberUploads: 1)
        
        let expectedFiles = [file]
        
        shouldSaveDownloads = { (downloads, next) in
            XCTAssert(downloads.count == 1)
            XCTAssert(self.filesHaveSameContents(url1: file.localURL, url2: downloads[0].downloadedFile as URL))
            
            next()
        }
        
        let expectation = self.expectation(description: "start")

        SyncManager.session.start { (result, error) in
            XCTAssert(error == nil)
            if case .shouldSaveDownloadsCalled(let numberDownloads) = result! {
                XCTAssert(numberDownloads == 1)
            }
            else {
                XCTFail()
            }
            
            let entries = DirectoryEntry.fetchAll()
            XCTAssert(entries.count == expectedFiles.count)

            for file in expectedFiles {
                let entriesResult = entries.filter { $0.fileUUID == file.fileUUID &&
                    $0.fileVersion == file.fileVersion
                }
                XCTAssert(entriesResult.count == 1)
            }
            
            expectation.fulfill()
        }
        
        waitForExpectations(timeout: 30.0, handler: nil)
    }
    
    func downloadTwoFiles(file1: ServerAPI.File, file2: ServerAPI.File, masterVersion:MasterVersionInt, completion:(()->())? = nil) {
        let expectedFiles = [file1, file2]
        
        doneUploads(masterVersion: masterVersion, expectedNumberUploads: 2)
        
        shouldSaveDownloads = { (downloads, next) in
            XCTAssert(downloads.count == 2)
            
            let result1 = downloads.filter {$0.downloadedFileAttributes.fileUUID == file1.fileUUID}
            XCTAssert(self.filesHaveSameContents(url1: file1.localURL, url2: result1[0].downloadedFile as URL))

            let result2 = downloads.filter {$0.downloadedFileAttributes.fileUUID == file2.fileUUID}
            XCTAssert(self.filesHaveSameContents(url1: file2.localURL, url2: result2[0].downloadedFile as URL))
            
            next()
        }
        
        let expectation = self.expectation(description: "start")

        SyncManager.session.start { (result, error) in
            XCTAssert(error == nil)
            if case .shouldSaveDownloadsCalled(let numberDownloads) = result! {
                XCTAssert(numberDownloads == 2)
            }
            else {
                XCTFail()
            }
            
            let entries = DirectoryEntry.fetchAll()
            XCTAssert(entries.count == expectedFiles.count)

            for file in expectedFiles {
                let entriesResult = entries.filter { $0.fileUUID == file.fileUUID &&
                    $0.fileVersion == file.fileVersion
                }
                XCTAssert(entriesResult.count == 1)
            }
            
            completion?()
            expectation.fulfill()
        }
        
        waitForExpectations(timeout: 30.0, handler: nil)
    }
    
    func uploadTwoFiles() -> (file1: ServerAPI.File, file2: ServerAPI.File, masterVersion:MasterVersionInt)? {
    
        let masterVersion = getMasterVersion()

        let fileUUID1 = UUID().uuidString
        let fileUUID2 = UUID().uuidString

        guard let (_, file1) = uploadFile(fileName: "UploadMe", fileExtension: "txt", mimeType: "text/plain", fileUUID: fileUUID1, serverMasterVersion: masterVersion) else {
            return nil
        }
        
        guard let (_, file2) = uploadFile(fileName: "UploadMe", fileExtension: "txt", mimeType: "text/plain", fileUUID: fileUUID2, serverMasterVersion: masterVersion) else {
            return nil
        }
        
        return (file1, file2, masterVersion)
    }
    
    func testStartWithTwoFilesOnServer() {
        guard let (file1, file2, masterVersion) = uploadTwoFiles() else {
            XCTFail()
            return
        }
        downloadTwoFiles(file1: file1, file2: file2, masterVersion: masterVersion)
    }
    
    func testWhereMasterVersionChangesMidwayThroughTwoDownloads() {
        var numberEvents = 0
 
        guard let (file1, file2, masterVersion) = uploadTwoFiles() else {
            XCTFail()
            return
        }
        
        let expectedFiles = [file1, file2]

        syncServerEventOccurred = { event in
            numberEvents += 1
            
            guard case .singleDownloadComplete(_, let attr) = event else {
                XCTFail()
                return
            }
            
            let result = expectedFiles.filter {$0.fileUUID == attr.fileUUID}
            XCTAssert(result.count == 1)
            XCTAssert(attr.fileVersion == result[0].fileVersion)
            
            if numberEvents == 1 {
                // This is fake: It would be conceptually better to upload a file here but that's a bit of a pain the way I have it setup in testing.
                MasterVersion.get().version = MasterVersion.get().version - 1
                CoreData.sessionNamed(Constants.coreDataName).saveContext()
            }
        }
        
        downloadTwoFiles(file1: file1, file2: file2, masterVersion: masterVersion) {
            // This will be three because the master version change with 1 download will reset downloads, and will cause the first download to occur a second time.
            XCTAssert(numberEvents == 3, "numberEvents was \(numberEvents)")
        }
    }
}

extension Client_SyncManager : SyncServerDelegate {
    func syncServerShouldSaveDownloads(downloads: [(downloadedFile: NSURL, downloadedFileAttributes: SyncAttributes)], next:()->()) {
        shouldSaveDownloads(downloads, next)
    }
    
    func syncServerEventOccurred(event: SyncEvent) {
        syncServerEventOccurred(event)
    }
}
