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
    override func setUp() {
        super.setUp()
        
        DownloadFileTracker.removeAll()
        DirectoryEntry.removeAll()
        CoreData.sessionNamed(Constants.coreDataName).saveContext()
        
        removeAllServerFilesInFileIndex()
    }
    
    override func tearDown() {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
        super.tearDown()
    }
    
    func testStartWithNoFilesOnServer() {
        let expectation = self.expectation(description: "next")

        syncServerEventOccurred = { event in
            XCTFail()
        }
        
        SyncManager.session.start { (error) in
            XCTAssert(error == nil)
            expectation.fulfill()
        }
        
        waitForExpectations(timeout: 30.0, handler: nil)
    }
    
    func testStartWithOneUploadedFileOnServer() {
        uploadAndDownloadOneFileUsingStart()
    }
    
    func downloadTwoFilesUsingStart(file1: ServerAPI.File, file2: ServerAPI.File, masterVersion:MasterVersionInt, useOwnSyncServerEventOccurred:Bool=true, completion:(()->())? = nil) {
        let expectedFiles = [file1, file2]
        
        doneUploads(masterVersion: masterVersion, expectedNumberUploads: 2)
        
        shouldSaveDownloads = { downloads in
            XCTAssert(downloads.count == 2)
            
            let result1 = downloads.filter {$0.downloadedFileAttributes.fileUUID == file1.fileUUID}
            XCTAssert(self.filesHaveSameContents(url1: file1.localURL, url2: result1[0].downloadedFile as URL))

            let result2 = downloads.filter {$0.downloadedFileAttributes.fileUUID == file2.fileUUID}
            XCTAssert(self.filesHaveSameContents(url1: file2.localURL, url2: result2[0].downloadedFile as URL))
        }
        
        let expectation = self.expectation(description: "start")
        
        var eventsOccurred = 0
        var downloadsCompleted = 0
        
        if useOwnSyncServerEventOccurred {
            syncServerEventOccurred = { event in
                switch event {
                case .fileDownloadsCompleted(numberOfFiles: let downloads):
                    XCTAssert(downloads == 2)
                    eventsOccurred += 1
                
                case .singleFileDownloadComplete(_):
                    downloadsCompleted += 1
                    
                default:
                    XCTFail()
                }
            }
        }
        
        SyncManager.session.start { (error) in
            XCTAssert(error == nil)
            
            let entries = DirectoryEntry.fetchAll()
            XCTAssert(entries.count == expectedFiles.count)

            for file in expectedFiles {
                let entriesResult = entries.filter { $0.fileUUID == file.fileUUID &&
                    $0.fileVersion == file.fileVersion
                }
                XCTAssert(entriesResult.count == 1)
            }
            
            if useOwnSyncServerEventOccurred {
                XCTAssert(downloadsCompleted == 2)
                XCTAssert(eventsOccurred == 1)
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

        let fileURL = Bundle(for: ServerAPI_UploadFile.self).url(forResource: "UploadMe", withExtension: "txt")!
        
        guard let (_, file1) = uploadFile(fileURL:fileURL, mimeType: "text/plain", fileUUID: fileUUID1, serverMasterVersion: masterVersion) else {
            return nil
        }
        
        guard let (_, file2) = uploadFile(fileURL:fileURL, mimeType: "text/plain", fileUUID: fileUUID2, serverMasterVersion: masterVersion) else {
            return nil
        }
        
        return (file1, file2, masterVersion)
    }
    
    func testStartWithTwoUploadedFilesOnServer() {
        guard let (file1, file2, masterVersion) = uploadTwoFiles() else {
            XCTFail()
            return
        }
        downloadTwoFilesUsingStart(file1: file1, file2: file2, masterVersion: masterVersion)
    }
    
    // Simulation of master version change on server-- by changing it locally.
    func testWhereMasterVersionChangesMidwayThroughTwoDownloads() {
        var numberEvents = 0
 
        guard let (file1, file2, masterVersion) = uploadTwoFiles() else {
            XCTFail()
            return
        }
        
        let expectedFiles = [file1, file2]
        var singleDownloads = 0
        
        syncServerEventOccurred = { event in
            numberEvents += 1
            
            switch event {
            case .singleFileDownloadComplete(url: _, attr: let attr):
                let result = expectedFiles.filter {$0.fileUUID == attr.fileUUID}
                XCTAssert(result.count == 1)
                let expectedFile = expectedFiles.filter {$0.fileUUID == attr.fileUUID}
                XCTAssert(expectedFile.count == 1)
                XCTAssert(expectedFile[0].fileVersion == result[0].fileVersion)
                singleDownloads += 1
                
            case .fileDownloadsCompleted(_):
                break
                
            default:
                XCTFail()
            }

            if numberEvents == 1 {
                // This is fake: It would be conceptually better to upload a file here but that's a bit of a pain the way I have it setup in testing.
                Singleton.get().masterVersion = Singleton.get().masterVersion - 1
                CoreData.sessionNamed(Constants.coreDataName).saveContext()
            }
        }
        
        downloadTwoFilesUsingStart(file1: file1, file2: file2, masterVersion: masterVersion, useOwnSyncServerEventOccurred:false) {
            XCTAssert(singleDownloads == 3, "singleDownloads was \(singleDownloads)")

            // This will be four because the master version change with 1 download will reset downloads, will cause the first download to occur a second time, and there will thus be 2 + 1 downloads.
            XCTAssert(numberEvents == 4, "numberEvents was \(numberEvents)")
        }
    }
}
