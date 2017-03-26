//
//  TestCase.swift
//  SyncServer
//
//  Created by Christopher Prince on 1/31/17.
//  Copyright © 2017 Spastic Muffin, LLC. All rights reserved.
//

import XCTest
import Foundation
@testable import SyncServer
import SMCoreLib

class TestCase: XCTestCase {
    let cloudFolderName = "Test.Folder"
    var authTokens = [String:String]()
    
    var deviceUUID = Foundation.UUID()
    var deviceUUIDUsed:Bool = false
    
    var testLockSync: TimeInterval?
    var testLockSyncCalled:Bool = false
    
    var shouldSaveDownloads: ((_ downloads: [(downloadedFile: NSURL, downloadedFileAttributes: SyncAttributes)]) -> ())!
    var syncServerEventOccurred: (SyncEvent) -> () = {event in }
    var shouldDoDeletions: (_ downloadDeletions: [SyncAttributes]) -> () = { downloadDeletions in }
    var syncServerErrorOccurred: (Error) -> () = { error in
        Log.error("syncServerErrorOccurred: \(error)")
    }
    
    var syncServerEventSingleUploadCompleted:((_ next: @escaping ()->())->())?
    
    // This value needs to be refreshed before running these tests.
    static let accessToken:String = {
        let plist = try! PlistDictLoader(plistFileNameInBundle: Consts.serverPlistFile)
        
        if case .stringValue(let value) = try! plist.getRequired(varName: "GoogleAccessToken") {
            return value
        }
        
        XCTFail()
        return ""
    }()
    
    override func setUp() {
        super.setUp()
        ServerAPI.session.delegate = self
        ServerNetworking.session.authenticationDelegate = self
        
        self.authTokens = [
            ServerConstants.XTokenTypeKey: ServerConstants.AuthTokenType.GoogleToken.rawValue,
            ServerConstants.GoogleHTTPAccessTokenKey: TestCase.accessToken
        ]
        
        SyncManager.session.delegate = self
    }
    
    override func tearDown() {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
        super.tearDown()
    }
    
    func getMasterVersion() -> MasterVersionInt {
        let expectation1 = self.expectation(description: "fileIndex")

        var serverMasterVersion:MasterVersionInt = 0
        
        ServerAPI.session.fileIndex { (fileIndex, masterVersion, error) in
            XCTAssert(error == nil)
            XCTAssert(masterVersion! >= 0)
            serverMasterVersion = masterVersion!
            expectation1.fulfill()
        }
        
        waitForExpectations(timeout: 10.0, handler: nil)
        
        return serverMasterVersion
    }
    
    @discardableResult
    func getFileIndex(expectedFiles:[(fileUUID:String, fileSize:Int64?)], callback:((FileInfo)->())? = nil) -> [FileInfo] {
        let expectation1 = self.expectation(description: "fileIndex")
        
        var result: [FileInfo]?
        
        ServerAPI.session.fileIndex { (fileIndex, masterVersion, error) in
            XCTAssert(error == nil)
            XCTAssert(masterVersion! >= 0)
            
            result = fileIndex
            
            for (fileUUID, fileSize) in expectedFiles {
                let result = fileIndex?.filter { file in
                    file.fileUUID == fileUUID
                }
                
                XCTAssert(result!.count == 1)
                
                if fileSize != nil {
                    XCTAssert(result![0].fileSizeBytes == fileSize)
                }
            }
            
            for curr in 0..<fileIndex!.count {
                callback?(fileIndex![curr])
            }
            
            expectation1.fulfill()
        }
        
        waitForExpectations(timeout: 10.0, handler: nil)
        
        return result!
    }
    
    func getUploads(expectedFiles:[(fileUUID:String, fileSize:Int64?)], callback:((FileInfo)->())? = nil) {
        let expectation1 = self.expectation(description: "getUploads")
        
        ServerAPI.session.getUploads { (uploads, error) in
            XCTAssert(error == nil)
            
            XCTAssert(expectedFiles.count == uploads?.count)
            
            for (fileUUID, fileSize) in expectedFiles {
                let result = uploads?.filter { file in
                    file.fileUUID == fileUUID
                }
                
                XCTAssert(result!.count == 1)
                if fileSize != nil {
                    XCTAssert(result![0].fileSizeBytes == fileSize)
                }
            }
            
            for curr in 0..<uploads!.count {
                callback?(uploads![curr])
            }
            
            expectation1.fulfill()
        }
        
        waitForExpectations(timeout: 10.0, handler: nil)
    }
    
    // Returns the file size uploaded
    func uploadFile(fileURL:URL, mimeType:String, fileUUID:String? = nil, serverMasterVersion:MasterVersionInt = 0, expectError:Bool = false, appMetaData:String? = nil, theDeviceUUID:String? = nil) -> (fileSize: Int64, ServerAPI.File)? {

        var uploadFileUUID:String
        if fileUUID == nil {
            uploadFileUUID = UUID().uuidString
        } else {
            uploadFileUUID = fileUUID!
        }
        
        var finalDeviceUUID:String
        if theDeviceUUID == nil {
            finalDeviceUUID = deviceUUID.uuidString
        }
        else {
            finalDeviceUUID = theDeviceUUID!
        }
        
        let file = ServerAPI.File(localURL: fileURL, fileUUID: uploadFileUUID, mimeType: mimeType, cloudFolderName: cloudFolderName, deviceUUID: finalDeviceUUID, appMetaData: appMetaData, fileVersion: 0)
        
        // Just to get the size-- this is redundant with the file read in ServerAPI.session.uploadFile
        guard let fileData = try? Data(contentsOf: file.localURL) else {
            XCTFail()
            return nil
        }
        
        let expectation = self.expectation(description: "upload")
        var fileSize:Int64?
        
        ServerAPI.session.uploadFile(file: file, serverMasterVersion: serverMasterVersion) { uploadFileResult, error in
            if expectError {
                XCTAssert(error != nil)
            }
            else {
                XCTAssert(error == nil)
                if case .success(let size) = uploadFileResult! {
                    XCTAssert(Int64(fileData.count) == size)
                    fileSize = size
                }
                else {
                    XCTFail()
                }
            }
            
            expectation.fulfill()
        }
        
        waitForExpectations(timeout: 30.0, handler: nil)
        
        if fileSize == nil {
            return nil
        }
        else {
            return (fileSize!, file)
        }
    }
    
    func uploadFile(fileName:String, fileExtension:String, mimeType:String, fileUUID:String? = nil, serverMasterVersion:MasterVersionInt = 0, withExpectation expectation:XCTestExpectation) {
    
        var uploadFileUUID:String
        if fileUUID == nil {
            uploadFileUUID = UUID().uuidString
        }
        else {
            uploadFileUUID = fileUUID!
        }
        
        let fileURL = Bundle(for: ServerAPI_UploadFile.self).url(forResource: fileName, withExtension: fileExtension)!

        let file = ServerAPI.File(localURL: fileURL, fileUUID: uploadFileUUID, mimeType: mimeType, cloudFolderName: cloudFolderName, deviceUUID: deviceUUID.uuidString, appMetaData: nil, fileVersion: 0)
        
        // Just to get the size-- this is redundant with the file read in ServerAPI.session.uploadFile
        guard let fileData = try? Data(contentsOf: file.localURL) else {
            XCTFail()
            return
        }
        
        Log.special("ServerAPI.session.uploadFile")
        
        ServerAPI.session.uploadFile(file: file, serverMasterVersion: serverMasterVersion) { uploadFileResult, error in
        
            XCTAssert(error == nil)
            if case .success(let size) = uploadFileResult! {
                XCTAssert(Int64(fileData.count) == size)
            }
            else {
                XCTFail()
            }
            
            expectation.fulfill()
        }
    }
    
    func doneUploads(masterVersion: MasterVersionInt, expectedNumberUploads:Int64) {
        let expectation = self.expectation(description: "doneUploads")

        ServerAPI.session.doneUploads(serverMasterVersion: masterVersion) {
            doneUploadsResult, error in
            
            XCTAssert(error == nil)
            if case .success(let numberUploads) = doneUploadsResult! {
                XCTAssert(numberUploads == expectedNumberUploads)
            }
            else {
                XCTFail()
            }
            
            expectation.fulfill()
        }
        
        waitForExpectations(timeout: 10.0, handler: nil)
    }
    
    func removeAllServerFilesInFileIndex() {
        let masterVersion = getMasterVersion()
        
        var filesToDelete:[FileInfo]?
        let uploadDeletion = self.expectation(description: "uploadDeletion")

        func recursiveRemoval(indexToRemove:Int) {
            if indexToRemove >= filesToDelete!.count {
                uploadDeletion.fulfill()
                return
            }
            
            let fileIndexObj = filesToDelete![indexToRemove]
            var fileToDelete = ServerAPI.FileToDelete(fileUUID: fileIndexObj.fileUUID, fileVersion: fileIndexObj.fileVersion)
            fileToDelete.actualDeletion = true
            
            ServerAPI.session.uploadDeletion(file: fileToDelete, serverMasterVersion: masterVersion) { (result, error) in
                XCTAssert(error == nil)
                guard case .success = result! else {
                    XCTFail()
                    return
                }
                
                recursiveRemoval(indexToRemove: indexToRemove + 1)
            }
        }
        
        ServerAPI.session.fileIndex { (fileIndex, masterVersion, error) in
            XCTAssert(error == nil)
            XCTAssert(masterVersion! >= 0)
            
            filesToDelete = fileIndex
            recursiveRemoval(indexToRemove: 0)
        }
        
        waitForExpectations(timeout: 30.0, handler: nil)
    }
    
    func filesHaveSameContents(url1: URL, url2: URL) -> Bool {
        
        let fileData1 = try? Data(contentsOf: url1 as URL)
        let fileData2 = try? Data(contentsOf: url2 as URL)
        
        if fileData1 == nil || fileData2 == nil {
            return false
        }
        
        return fileData1! == fileData2!
    }

    @discardableResult
    // Uses SyncManager.session.start
    func uploadAndDownloadOneFileUsingStart() -> (ServerAPI.File, MasterVersionInt)? {
        let masterVersion = getMasterVersion()
        
        let fileUUID = UUID().uuidString
        let fileURL = Bundle(for: ServerAPI_UploadFile.self).url(forResource: "UploadMe", withExtension: "txt")!
        
        guard let (_, file) = uploadFile(fileURL:fileURL, mimeType: "text/plain", fileUUID: fileUUID, serverMasterVersion: masterVersion) else {
            return nil
        }
        
        doneUploads(masterVersion: masterVersion, expectedNumberUploads: 1)
        
        let expectedFiles = [file]
        
        shouldSaveDownloads = { downloads in
            XCTAssert(downloads.count == 1)
            XCTAssert(self.filesHaveSameContents(url1: file.localURL, url2: downloads[0].downloadedFile as URL))
        }
        
        let expectation = self.expectation(description: "start")

        var eventsOccurred = 0
        var downloadsOccurred = 0
        
        syncServerEventOccurred = { event in
            switch event {
            case .fileDownloadsCompleted(numberOfFiles: let downloads):
                XCTAssert(downloads == 1)
                eventsOccurred += 1
            
            case .singleFileDownloadComplete(_):
                downloadsOccurred += 1
                
            default:
                XCTFail()
            }
        }

        SyncManager.session.start { (error) in
            XCTAssert(error == nil)
            
            let entries = DirectoryEntry.fetchAll()
            
            // There may be more directory entries than just accounted for in this single function call, so don't do this:
            //XCTAssert(entries.count == expectedFiles.count)

            for file in expectedFiles {
                let entriesResult = entries.filter { $0.fileUUID == file.fileUUID &&
                    $0.fileVersion == file.fileVersion
                }
                XCTAssert(entriesResult.count == 1)
            }
            
            XCTAssert(downloadsOccurred == 1)
            XCTAssert(eventsOccurred == 1)
            expectation.fulfill()
        }
        
        waitForExpectations(timeout: 30.0, handler: nil)
        
        return (file, masterVersion + 1)
    }

    @discardableResult
    func uploadDeletion() -> (fileUUID:String, MasterVersionInt)? {
        let masterVersion = getMasterVersion()
        
        let fileUUID = UUID().uuidString
        let fileURL = Bundle(for: ServerAPI_UploadFile.self).url(forResource: "UploadMe", withExtension: "txt")!
        
        guard let (_, file) = uploadFile(fileURL:fileURL, mimeType: "text/plain", fileUUID: fileUUID, serverMasterVersion: masterVersion) else {
            return nil
        }
        
        // for the file upload
        doneUploads(masterVersion: masterVersion, expectedNumberUploads: 1)

        let fileToDelete = ServerAPI.FileToDelete(fileUUID: file.fileUUID, fileVersion: file.fileVersion)
        uploadDeletion(fileToDelete: fileToDelete, masterVersion: masterVersion+1)
        
        getUploads(expectedFiles: [
            (fileUUID: fileUUID, fileSize: nil)
        ]) { fileInfo in
            XCTAssert(fileInfo.deleted)
        }
        
        return (fileUUID, masterVersion+1)
    }
    
    func uploadDeletion(fileToDelete:ServerAPI.FileToDelete, masterVersion:MasterVersionInt) {
        let uploadDeletion = self.expectation(description: "uploadDeletion")

        ServerAPI.session.uploadDeletion(file: fileToDelete, serverMasterVersion: masterVersion) { (result, error) in
            XCTAssert(error == nil)
            guard case .success = result! else {
                XCTFail()
                return
            }
            uploadDeletion.fulfill()
        }
        
        waitForExpectations(timeout: 10.0, handler: nil)
    }

    func uploadDeletionOfOneFileWithDoneUploads() {
        guard let (fileUUID, masterVersion) = uploadDeletion() else {
            XCTFail()
            return
        }

        self.doneUploads(masterVersion: masterVersion, expectedNumberUploads: 1)
        
        self.getUploads(expectedFiles: []) { file in
            XCTAssert(file.fileUUID != fileUUID)
        }
        
        var foundDeletedFile = false
        
        getFileIndex(expectedFiles: [
            (fileUUID: fileUUID, fileSize: nil)
        ]) { file in
            if file.fileUUID == fileUUID {
                foundDeletedFile = true
                XCTAssert(file.deleted)
            }
        }
        
        XCTAssert(foundDeletedFile)
    }
    
    func uploadAndDownloadTextFile(appMetaData:String? = nil, uploadFileURL:URL = Bundle(for: TestCase.self).url(forResource: "UploadMe", withExtension: "txt")!, fileUUID:String? = nil) {
    
        let masterVersion = getMasterVersion()
        
        var actualFileUUID:String! = fileUUID
        if fileUUID == nil {
            actualFileUUID = UUID().uuidString
        }
        
        guard let (fileSize, file) = uploadFile(fileURL:uploadFileURL, mimeType: "text/plain", fileUUID: actualFileUUID, serverMasterVersion: masterVersion, appMetaData:appMetaData) else {
            return
        }
        
        doneUploads(masterVersion: masterVersion, expectedNumberUploads: 1)
        
        onlyDownloadFile(comparisonFileURL: uploadFileURL, file: file, masterVersion: masterVersion + 1, appMetaData: appMetaData, fileSize: fileSize)
    }
    
    func onlyDownloadFile(comparisonFileURL:URL, file:Filenaming, masterVersion:MasterVersionInt, appMetaData:String? = nil, fileSize:Int64? = nil) {
        let expectation = self.expectation(description: "doneUploads")

        ServerAPI.session.downloadFile(file: file, serverMasterVersion: masterVersion) { (result, error) in
        
            XCTAssert(error == nil)
            XCTAssert(result != nil)
            
            if case .success(let downloadedFile) = result! {
                XCTAssert(FilesMisc.compareFiles(file1: comparisonFileURL, file2: downloadedFile.url as URL))
                if appMetaData != nil {
                    XCTAssert(downloadedFile.appMetaData == appMetaData)
                }
                if fileSize != nil {
                    XCTAssert(fileSize == downloadedFile.fileSizeBytes)
                }
            }
            else {
                XCTFail()
            }
            
            expectation.fulfill()
        }
        
        waitForExpectations(timeout: 10.0, handler: nil)
    }
    
    func uploadSingleFileUsingSync() -> (URL, SyncAttributes) {
        let url = SMRelativeLocalURL(withRelativePath: "UploadMe2.txt", toBaseURLType: .mainBundle)!
        let fileUUID = UUID().uuidString
        let attr = SyncAttributes(fileUUID: fileUUID, mimeType: "text/plain")
        
        SyncServer.session.eventsDesired = [.syncDone, .fileUploadsCompleted, .singleFileUploadComplete]
        let expectation1 = self.expectation(description: "test1")
        let expectation2 = self.expectation(description: "test2")
        let expectation3 = self.expectation(description: "test3")
        
        syncServerEventOccurred = {event in
            switch event {
            case .syncDone:
                expectation1.fulfill()
                
            case .fileUploadsCompleted(numberOfFiles: let number):
                XCTAssert(number == 1)
                expectation2.fulfill()
                
            case .singleFileUploadComplete(attr: let attr):
                XCTAssert(attr.fileUUID == fileUUID)
                XCTAssert(attr.mimeType == "text/plain")
                expectation3.fulfill()
                
            default:
                XCTFail()
            }
        }
        
        try! SyncServer.session.uploadImmutable(localFile: url, withAttributes: attr)
        SyncServer.session.sync()
        
        waitForExpectations(timeout: 20.0, handler: nil)
        
        return (url as URL, attr)
    }
}

extension TestCase : ServerNetworkingAuthentication {
    func headerAuthentication(forServerNetworking: ServerNetworking) -> [String:String]? {
        var result = [String:String]()
        for (key, value) in self.authTokens {
            result[key] = value
        }
        
        result[ServerConstants.httpRequestDeviceUUID] = self.deviceUUID.uuidString
        deviceUUIDUsed = true
        
        return result
    }
}

extension TestCase : ServerAPIDelegate {
    func doneUploadsRequestTestLockSync(forServerAPI: ServerAPI) -> TimeInterval? {
        testLockSyncCalled = true
        return testLockSync
    }
    
    func deviceUUID(forServerAPI: ServerAPI) -> Foundation.UUID {
        return deviceUUID
    }
}

extension TestCase : SyncServerDelegate {
    func shouldSaveDownloads(downloads: [(downloadedFile: NSURL, downloadedFileAttributes: SyncAttributes)]) {
        shouldSaveDownloads(downloads)
    }
    
    func syncServerEventOccurred(event: SyncEvent) {
        syncServerEventOccurred(event)
    }
    
    func shouldDoDeletions(downloadDeletions: [SyncAttributes]) {
        shouldDoDeletions(downloadDeletions)
    }
    
    func syncServerErrorOccurred(error:Error) {
        syncServerErrorOccurred(error)
    }
    
    func syncServerEventSingleUploadCompleted(next: @escaping ()->()) {
        if syncServerEventSingleUploadCompleted == nil {
            next()
        }
        else {
            syncServerEventSingleUploadCompleted!(next)
        }
    }
}
