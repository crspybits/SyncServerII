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
        CoreData.sessionNamed(Constants.coreDataName).saveContext()

        removeAllServerFilesInFileIndex()
    }
    
    override func tearDown() {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
        super.tearDown()
    }
    
    func checkForDownloads(expectedMasterVersion:MasterVersionInt, expectedFiles:[ServerAPI.File]) {
        
        let expectation = self.expectation(description: "check")

        Download.session.check() { checkCompletion in
            switch checkCompletion {
            case .noDownloadsOrDeletionsAvailable:
                XCTAssert(expectedFiles.count == 0)
                
            case .downloadsOrDeletionsAvailable(numberOfFiles: let numDownloads):
                XCTAssert(Int32(expectedFiles.count) == numDownloads)
                
            case .error(_):
                XCTFail()
            }
            
            XCTAssert(MasterVersion.get().version == expectedMasterVersion)

            let dfts = DownloadFileTracker.fetchAll()
            XCTAssert(dfts.count == expectedFiles.count)

            for file in expectedFiles {
                let dftsResult = dfts.filter { $0.fileUUID == file.fileUUID &&
                    $0.fileVersion == file.fileVersion
                }
                XCTAssert(dftsResult.count == 1)
            }
            
            let entries = DirectoryEntry.fetchAll()
            XCTAssert(entries.count == 0)
            
            expectation.fulfill()
        }
        
        waitForExpectations(timeout: 30.0, handler: nil)
    }
    
    func testCheckForDownloadOfZeroFilesWorks() {
        let masterVersion = getMasterVersion()
        checkForDownloads(expectedMasterVersion: masterVersion, expectedFiles: [])
    }
    
    func testCheckForDownloadOfSingleFileWorks() {
        let masterVersion = getMasterVersion()
        
        let fileUUID = UUID().uuidString
        
        guard let (_, file) = uploadFile(fileName: "UploadMe", fileExtension: "txt", mimeType: "text/plain", fileUUID: fileUUID, serverMasterVersion: masterVersion) else {
            return
        }
        
        doneUploads(masterVersion: masterVersion, expectedNumberUploads: 1)
        
        checkForDownloads(expectedMasterVersion: masterVersion + 1, expectedFiles: [file])
    }
    
    func testCheckForDownloadOfTwoFilesWorks() {
        let masterVersion = getMasterVersion()
        
        let fileUUID1 = UUID().uuidString
        let fileUUID2 = UUID().uuidString

        guard let (_, file1) = uploadFile(fileName: "UploadMe", fileExtension: "txt", mimeType: "text/plain", fileUUID: fileUUID1, serverMasterVersion: masterVersion) else {
            return
        }
        
        guard let (_, file2) = uploadFile(fileName: "UploadMe", fileExtension: "txt", mimeType: "text/plain", fileUUID: fileUUID2, serverMasterVersion: masterVersion) else {
            return
        }
        
        doneUploads(masterVersion: masterVersion, expectedNumberUploads: 2)
        
        checkForDownloads(expectedMasterVersion: masterVersion + 1, expectedFiles: [file1, file2])
    }
    
    func testDownloadNextWithNoFilesOnServer() {
        let masterVersion = getMasterVersion()
        checkForDownloads(expectedMasterVersion: masterVersion, expectedFiles: [])
    
        let result = Download.session.next() { completionResult in
            XCTFail()
        }
        
        guard case .noDownloadsOrDeletions = result else {
            XCTFail()
            return
        }
    }
    
    func testDownloadNextWithOneFileNotDownloadedOnServer() {
        let masterVersion = getMasterVersion()
        
        let fileUUID = UUID().uuidString
        
        guard let (_, file) = uploadFile(fileName: "UploadMe", fileExtension: "txt", mimeType: "text/plain", fileUUID: fileUUID, serverMasterVersion: masterVersion) else {
            return
        }
        
        doneUploads(masterVersion: masterVersion, expectedNumberUploads: 1)
        
        checkForDownloads(expectedMasterVersion: masterVersion + 1, expectedFiles: [file])

        let expectation = self.expectation(description: "next")

        let result = Download.session.next() { completionResult in
            guard case .downloaded = completionResult else {
                XCTFail()
                return
            }
            
            let dfts = DownloadFileTracker.fetchAll()
            XCTAssert(dfts[0].appMetaData == nil)
            XCTAssert(dfts[0].fileVersion == file.fileVersion)
            XCTAssert(dfts[0].status == .downloaded)

            let fileData1 = try? Data(contentsOf: file.localURL)
            XCTAssert(Int64(fileData1!.count) == dfts[0].fileSizeBytes)
            XCTAssert(self.filesHaveSameContents(url1: file.localURL, url2: dfts[0].localURL! as URL))
            
            expectation.fulfill()
        }
        
        guard case .started = result else {
            XCTFail()
            return
        }
        
        let dfts = DownloadFileTracker.fetchAll()
        XCTAssert(dfts[0].status == .downloading)
        
        waitForExpectations(timeout: 30.0, handler: nil)
    }
    
    func testDownloadNextWithMasterVersionUpdate() {
        let masterVersion = getMasterVersion()
        
        let fileUUID = UUID().uuidString
        
        guard let (_, file) = uploadFile(fileName: "UploadMe", fileExtension: "txt", mimeType: "text/plain", fileUUID: fileUUID, serverMasterVersion: masterVersion) else {
            return
        }
        
        doneUploads(masterVersion: masterVersion, expectedNumberUploads: 1)
        
        checkForDownloads(expectedMasterVersion: masterVersion + 1, expectedFiles: [file])
        
        // Fake an incorrect master version.
        MasterVersion.get().version = masterVersion
        CoreData.sessionNamed(Constants.coreDataName).saveContext()

        let expectation = self.expectation(description: "next")

        let result = Download.session.next() { completionResult in
            guard case .masterVersionUpdate = completionResult else {
                XCTFail()
                return
            }
            
            expectation.fulfill()
        }
        
        guard case .started = result else {
            XCTFail()
            return
        }
        
        let dfts = DownloadFileTracker.fetchAll()
        XCTAssert(dfts[0].status == .downloading)
        
        waitForExpectations(timeout: 30.0, handler: nil)
    }
    
    func testThatTwoNextsWithOneFileGivesAllDownloadsCompleted() {
        let masterVersion = getMasterVersion()
        
        let fileUUID = UUID().uuidString
        
        guard let (_, file) = uploadFile(fileName: "UploadMe", fileExtension: "txt", mimeType: "text/plain", fileUUID: fileUUID, serverMasterVersion: masterVersion) else {
            return
        }
        
        doneUploads(masterVersion: masterVersion, expectedNumberUploads: 1)
        
        checkForDownloads(expectedMasterVersion: masterVersion + 1, expectedFiles: [file])

        // First next should work as usual
        let expectation1 = self.expectation(description: "next1")
        let _ = Download.session.next() { completionResult in
            guard case .downloaded = completionResult else {
                XCTFail()
                return
            }
            
            expectation1.fulfill()
        }
        waitForExpectations(timeout: 30.0, handler: nil)
        
        // Second next should indicate `allDownloadsCompleted`
        let result = Download.session.next() { completionResult in
            XCTFail()
        }
        
        guard case .allDownloadsCompleted = result else {
            XCTFail()
            return
        }
    }
    
    func testNextImmediatelyFollowedByNextIndicatesDownloadAlreadyOccurring() {
        let masterVersion = getMasterVersion()
        
        let fileUUID = UUID().uuidString
        
        guard let (_, file) = uploadFile(fileName: "UploadMe", fileExtension: "txt", mimeType: "text/plain", fileUUID: fileUUID, serverMasterVersion: masterVersion) else {
            return
        }
        
        doneUploads(masterVersion: masterVersion, expectedNumberUploads: 1)
        
        checkForDownloads(expectedMasterVersion: masterVersion + 1, expectedFiles: [file])

        let expectation = self.expectation(description: "next")

        let _ = Download.session.next() { completionResult in
            guard case .downloaded = completionResult else {
                XCTFail()
                return
            }
            
            expectation.fulfill()
        }
        
        // This second `next` should fail: We already have a download occurring.
        let result = Download.session.next() { completionResult in
            XCTFail()
        }
        guard case .error(_) = result else {
            XCTFail()
            return
        }
        
        waitForExpectations(timeout: 30.0, handler: nil)
    }
}
