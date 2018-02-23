//
//  FileController_MultiVersionFiles.swift
//  Server
//
//  Created by Christopher Prince on 1/7/18.
//
//

import XCTest
@testable import Server
import LoggerAPI
import Foundation
import PerfectLib
import SyncServerShared

class FileController_MultiVersionFiles: ServerTestCase, LinuxTestable {

    override func setUp() {
        super.setUp()
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }
    
    override func tearDown() {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
        super.tearDown()
    }
    
    // MARK: Upload

    func uploadNextFileVersion(uploadRequest: UploadFileRequest, masterVersion: MasterVersionInt, fileVersionToUpload:FileVersionInt, creationDate: Date, mimeType: String, appMetaData: String, fileSize:Int64) {
    
        guard let healthCheck1 = healthCheck() else {
            XCTFail()
            return
        }
        
        // The use of a different device UUID here is part of this test-- that the second version can be uploaded with a different device UUID.
        let deviceUUID = PerfectLib.UUID().string
        _ = uploadTextFile(deviceUUID: deviceUUID, fileUUID: uploadRequest.fileUUID, addUser: false, fileVersion:fileVersionToUpload, masterVersion: masterVersion)
        sendDoneUploads(expectedNumberOfUploads: 1, deviceUUID:deviceUUID, masterVersion: masterVersion)
        
        guard let healthCheck2 = healthCheck() else {
            XCTFail()
            return
        }
        
        // New upload device UUID will go into the FileIndex as that of the new uploading device.
        getFileIndex(deviceUUID: deviceUUID) { fileInfoArray in
            guard let fileInfoArray = fileInfoArray, fileInfoArray.count == 1 else {
                XCTFail()
                return
            }
            
            let result = fileInfoArray.filter({$0.fileUUID == uploadRequest.fileUUID})
            guard result.count == 1 else {
                XCTFail()
                return
            }
            
            XCTAssert(result[0].deviceUUID == deviceUUID)
            XCTAssert(result[0].fileVersion == 1)

            // Make sure updateDate has changed appropriately (server should establish this). Make sure that creationDate hasn't changed.
            XCTAssert(healthCheck1.currentServerDateTime <= result[0].updateDate!)
            XCTAssert(healthCheck2.currentServerDateTime >= result[0].updateDate!)
            
            XCTAssert(result[0].creationDate == creationDate)
            
            XCTAssert(result[0].mimeType == mimeType)
            XCTAssert(result[0].appMetaData == appMetaData)
            XCTAssert(result[0].deleted == false)
            XCTAssert(result[0].fileVersion == fileVersionToUpload)
            XCTAssert(result[0].fileSizeBytes == fileSize)
        }
        
        guard let _ = self.downloadTextFile(masterVersionExpectedWithDownload: Int(masterVersion + 1), appMetaData: appMetaData, downloadFileVersion: fileVersionToUpload, uploadFileRequest: uploadRequest, fileSize: fileSize) else {
            XCTFail()
            return
        }
    }
    
    // Also tests to make sure a different device UUID can upload the second version.
    func testUploadVersion1AfterVersion0Works() {
        let mimeType = "text/plain"
        let appMetaData = "Some-App-Meta-Data"
        let fileVersion:FileVersionInt = 1
        let deviceUUID1 = PerfectLib.UUID().string
        
        let (uploadRequest, fileSize) = uploadTextFile(deviceUUID: deviceUUID1, appMetaData:appMetaData)
        // Send DoneUploads-- to commit version 0.
        sendDoneUploads(expectedNumberOfUploads: 1, deviceUUID:deviceUUID1)
        
        var creationDate:Date!
        
        getFileIndex(deviceUUID: deviceUUID1) { fileInfoArray in
            guard let fileInfoArray = fileInfoArray, fileInfoArray.count == 1 else {
                XCTFail()
                return
            }
            
            creationDate = fileInfoArray[0].creationDate
        }
        
        guard creationDate != nil else {
            XCTFail()
            return
        }
        
        uploadNextFileVersion(uploadRequest: uploadRequest, masterVersion: 1, fileVersionToUpload:fileVersion, creationDate: creationDate!, mimeType: mimeType, appMetaData: appMetaData, fileSize:fileSize)
    }
    
    // Attempt to upload version 1 when version 0 hasn't yet been committed with DoneUploads-- should fail.
    func testUploadVersion1WhenVersion0HasNotBeenCommitted() {
        let deviceUUID1 = PerfectLib.UUID().string
        let (request, _) = uploadTextFile(deviceUUID: deviceUUID1)
        
        let deviceUUID2 = PerfectLib.UUID().string

        _ = uploadTextFile(deviceUUID: deviceUUID2, fileUUID: request.fileUUID, addUser: false, fileVersion:1, masterVersion: 0, errorExpected: true)
    }

    // Upload version N of a file; do DoneUploads. Then try again to upload version N. That should fail.
    func testUploadOfSameFileVersionFails() {
        let deviceUUID1 = PerfectLib.UUID().string
        let (request, _) = uploadTextFile(deviceUUID: deviceUUID1)
        // Send DoneUploads-- to commit version 0.
        sendDoneUploads(expectedNumberOfUploads: 1, deviceUUID:deviceUUID1)
        
        let deviceUUID2 = PerfectLib.UUID().string

        _ = uploadTextFile(deviceUUID: deviceUUID2, fileUUID: request.fileUUID, addUser: false, fileVersion:0, masterVersion: 1, errorExpected: true)
        
        getFileIndex(deviceUUID: deviceUUID1) { fileInfoArray in
            guard let fileInfoArray = fileInfoArray, fileInfoArray.count == 1 else {
                XCTFail()
                return
            }
            
            let result = fileInfoArray.filter({$0.fileUUID == request.fileUUID})
            guard result.count == 1 else {
                XCTFail()
                return
            }
            
            XCTAssert(result[0].deviceUUID == deviceUUID1)
            XCTAssert(result[0].fileVersion == 0)
        }
    }

    func testUploadVersion1OfNewFileFails() {
        _ = uploadTextFile(fileVersion:1, errorExpected: true)
    }
    
    let appMetaData = "Some-App-Meta-Data"
    
    @discardableResult
    // Master version after this call is sent back.
    func uploadVersion(_ version: FileVersionInt, deviceUUID:String = PerfectLib.UUID().string, fileUUID:String, startMasterVersion: MasterVersionInt = 0, addUser:Bool = true) -> (MasterVersionInt, UploadFileRequest) {
        
        var masterVersion:MasterVersionInt = startMasterVersion

        let (uploadRequest, _) = uploadTextFile(deviceUUID: deviceUUID, fileUUID:fileUUID, addUser:addUser, masterVersion:masterVersion, appMetaData:appMetaData)
        // Send DoneUploads-- to commit version 0.
        sendDoneUploads(expectedNumberOfUploads: 1, deviceUUID:deviceUUID, masterVersion:masterVersion)
        
        masterVersion += 1
        var fileVersion:FileVersionInt = 1

        for _ in 1...version {
            _ = uploadTextFile(deviceUUID: deviceUUID, fileUUID: uploadRequest.fileUUID, addUser: false, fileVersion:fileVersion, masterVersion: masterVersion)
            sendDoneUploads(expectedNumberOfUploads: 1, deviceUUID:deviceUUID, masterVersion: masterVersion)
            
            fileVersion += 1
            masterVersion += 1
        }
        
        return (masterVersion, uploadRequest)
    }
    
    // Upload some number (e.g., 5) of new versions.
    func testSuccessiveUploadsOfNextVersionWorks() {
        let fileUUID = PerfectLib.UUID().string
        uploadVersion(5, fileUUID:fileUUID)
    }
    
    func testUploadDifferentFileContentsForSecondVersionWorks() {
        // Upload small text file first.
        let deviceUUID1 = PerfectLib.UUID().string
        
        let (uploadRequest, _) = uploadTextFile(deviceUUID: deviceUUID1, appMetaData:appMetaData)
        // Send DoneUploads-- to commit version 0.
        sendDoneUploads(expectedNumberOfUploads: 1, deviceUUID:deviceUUID1, masterVersion: 0)
        
        let fileContentsV2 = "This is some longer text that I'm typing here and hopefullly I don't get too bored"
        
        // Then upload some other text contents -- as version 1 of the same file.
        let (uploadRequest2, fileSize2) = uploadTextFile(deviceUUID: deviceUUID1, fileUUID:uploadRequest.fileUUID, addUser: false, fileVersion: 1, masterVersion: 1, appMetaData:appMetaData, contents: fileContentsV2)
        
        sendDoneUploads(expectedNumberOfUploads: 1, deviceUUID:deviceUUID1, masterVersion: 1)
        
        // Make sure the file contents are right.
        getFileIndex(deviceUUID: deviceUUID1) { fileInfoArray in
            guard let fileInfoArray = fileInfoArray, fileInfoArray.count == 1 else {
                XCTFail()
                return
            }
            
            let result = fileInfoArray.filter({$0.fileUUID == uploadRequest.fileUUID})
            guard result.count == 1 else {
                XCTFail()
                return
            }
        }
        
        guard let _ = self.downloadTextFile(masterVersionExpectedWithDownload: 2, appMetaData: self.appMetaData, downloadFileVersion: 1, uploadFileRequest: uploadRequest2, fileSize: fileSize2) else {
            XCTFail()
            return
        }
    }
    
    // Next version uploaded must be +1
    func testUploadOfVersion2OfVersion0FileFails() {
        let deviceUUID1 = PerfectLib.UUID().string
        let (request, _) = uploadTextFile(deviceUUID: deviceUUID1)
        // Send DoneUploads-- to commit version 0.
        sendDoneUploads(expectedNumberOfUploads: 1, deviceUUID:deviceUUID1)
        
        let deviceUUID2 = PerfectLib.UUID().string
        _ = uploadTextFile(deviceUUID: deviceUUID2, fileUUID: request.fileUUID, addUser: false, fileVersion:2, masterVersion: 1, errorExpected: true)
    }
    
    func testUploadOfTwoConsecutiveVersionsWithoutADoneUploadsAfterVersion0IsUploadedFails() {
        let deviceUUID1 = PerfectLib.UUID().string
        let (request, _) = uploadTextFile(deviceUUID: deviceUUID1)
        // Send DoneUploads-- to commit version 0.
        sendDoneUploads(expectedNumberOfUploads: 1, deviceUUID:deviceUUID1)
        
        let deviceUUID2 = PerfectLib.UUID().string
        _ = uploadTextFile(deviceUUID: deviceUUID2, fileUUID: request.fileUUID, addUser: false, fileVersion:1, masterVersion: 1, errorExpected: false)

        _ = uploadTextFile(deviceUUID: deviceUUID2, fileUUID: request.fileUUID, addUser: false, fileVersion:2, masterVersion: 1, errorExpected: true)
    }
    
    // MARK: Upload deletion.

    // Upload version 0. Try to delete version 1.
    func testUploadDeletionOfVersionThatDoesNotExistFails() {
        let deviceUUID1 = PerfectLib.UUID().string
        let (request, _) = uploadTextFile(deviceUUID: deviceUUID1)
        // Send DoneUploads-- to commit version 0.
        sendDoneUploads(expectedNumberOfUploads: 1, deviceUUID:deviceUUID1)

        let uploadDeletionRequest = UploadDeletionRequest(json: [
            UploadDeletionRequest.fileUUIDKey: request.fileUUID,
            UploadDeletionRequest.fileVersionKey: request.fileVersion + 1,
            UploadDeletionRequest.masterVersionKey: request.masterVersion + MasterVersionInt(1)
        ])!
        
        uploadDeletion(uploadDeletionRequest: uploadDeletionRequest, deviceUUID: deviceUUID1, addUser: false, expectError: true)
    }
    
    func testUploadDeletionOfVersionThatExistsWorks() {
        let fileUUID = PerfectLib.UUID().string
        let (masterVersion, _) = uploadVersion(2, fileUUID:fileUUID)
        
        let uploadDeletionRequest = UploadDeletionRequest(json: [
            UploadDeletionRequest.fileUUIDKey: fileUUID,
            UploadDeletionRequest.fileVersionKey: 2,
            UploadDeletionRequest.masterVersionKey: masterVersion
        ])!
        
        let deviceUUID = PerfectLib.UUID().string
        uploadDeletion(uploadDeletionRequest: uploadDeletionRequest, deviceUUID: deviceUUID, addUser: false)
        sendDoneUploads(expectedNumberOfUploads: 1, deviceUUID: deviceUUID, masterVersion: masterVersion)
    }
    
    func checkFileIndex(deviceUUID:String, fileUUID:String, fileVersion:Int32) {
        getFileIndex(deviceUUID: deviceUUID) { fileInfoArray in
            guard let fileInfoArray = fileInfoArray else {
                XCTFail()
                return
            }
            
            let result = fileInfoArray.filter({$0.fileUUID == fileUUID})
            guard result.count == 1 else {
                XCTFail()
                return
            }
            
            XCTAssert(result[0].deviceUUID == deviceUUID)
            XCTAssert(result[0].fileVersion == fileVersion)
        }
    }
    
    // MARK: File Index

    func testFileIndexReportsVariousFileVersions() {
        let fileUUID1 = PerfectLib.UUID().string
        let fileUUID2 = PerfectLib.UUID().string
        let fileUUID3 = PerfectLib.UUID().string
        let deviceUUID = PerfectLib.UUID().string

        var (masterVersion, _) = uploadVersion(2, deviceUUID: deviceUUID, fileUUID:fileUUID1)
        (masterVersion, _) = uploadVersion(3, deviceUUID: deviceUUID, fileUUID:fileUUID2, startMasterVersion: masterVersion, addUser: false)
        (masterVersion, _) = uploadVersion(5, deviceUUID: deviceUUID, fileUUID:fileUUID3, startMasterVersion: masterVersion, addUser: false)

        checkFileIndex(deviceUUID:deviceUUID, fileUUID:fileUUID1, fileVersion:2)
        checkFileIndex(deviceUUID:deviceUUID, fileUUID:fileUUID2, fileVersion:3)
        checkFileIndex(deviceUUID:deviceUUID, fileUUID:fileUUID3, fileVersion:5)
    }
    
    // MARK: Download
    
    func testDownloadOfFileVersion3Works() {
        let fileUUID1 = PerfectLib.UUID().string
        let deviceUUID = PerfectLib.UUID().string
        let fileVersion:FileVersionInt = 3
        let (masterVersion, uploadRequest) = uploadVersion(fileVersion, deviceUUID: deviceUUID, fileUUID:fileUUID1)
        
        guard let _ = downloadTextFile(masterVersionExpectedWithDownload: Int(masterVersion), appMetaData: appMetaData, downloadFileVersion: fileVersion, uploadFileRequest: uploadRequest, fileSize: Int64(ServerTestCase.uploadTextFileContents.count)) else {
            XCTFail()
            return
        }
    }
    
    func testDownloadOfBadVersionFails() {
        let fileUUID1 = PerfectLib.UUID().string
        let deviceUUID = PerfectLib.UUID().string
        let fileVersion:FileVersionInt = 3
        let (masterVersion, uploadRequest) = uploadVersion(fileVersion, deviceUUID: deviceUUID, fileUUID:fileUUID1)
        
        downloadTextFile(masterVersionExpectedWithDownload: Int(masterVersion), appMetaData: appMetaData, downloadFileVersion: fileVersion+1, uploadFileRequest: uploadRequest, fileSize: Int64(ServerTestCase.uploadTextFileContents.count), expectedError: true)
    }
}

extension FileController_MultiVersionFiles {
    static var allTests : [(String, (FileController_MultiVersionFiles) -> () throws -> Void)] {
        return [
            ("testUploadVersion1AfterVersion0Works", testUploadVersion1AfterVersion0Works),
            ("testUploadVersion1WhenVersion0HasNotBeenCommitted", testUploadVersion1WhenVersion0HasNotBeenCommitted),
            ("testUploadOfSameFileVersionFails", testUploadOfSameFileVersionFails),
            ("testUploadVersion1OfNewFileFails", testUploadVersion1OfNewFileFails),
            ("testSuccessiveUploadsOfNextVersionWorks", testSuccessiveUploadsOfNextVersionWorks),
            ("testUploadDifferentFileContentsForSecondVersionWorks", testUploadDifferentFileContentsForSecondVersionWorks),
            ("testUploadOfVersion2OfVersion0FileFails", testUploadOfVersion2OfVersion0FileFails),
            ("testUploadOfTwoConsecutiveVersionsWithoutADoneUploadsAfterVersion0IsUploadedFails", testUploadOfTwoConsecutiveVersionsWithoutADoneUploadsAfterVersion0IsUploadedFails),
            ("testUploadDeletionOfVersionThatDoesNotExistFails", testUploadDeletionOfVersionThatDoesNotExistFails),
            ("testUploadDeletionOfVersionThatExistsWorks", testUploadDeletionOfVersionThatExistsWorks),
            ("testFileIndexReportsVariousFileVersions", testFileIndexReportsVariousFileVersions),
            ("testDownloadOfFileVersion3Works", testDownloadOfFileVersion3Works),
            ("testDownloadOfBadVersionFails", testDownloadOfBadVersionFails),
            ("testDownloadOfBadVersionFails", testDownloadOfBadVersionFails)
        ]
    }
    
    func testLinuxTestSuiteIncludesAllTests() {
        linuxTestSuiteIncludesAllTests(testType:FileController_MultiVersionFiles.self)
    }
}
