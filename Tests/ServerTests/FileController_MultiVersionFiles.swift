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
            
            XCTAssert(result[0].cloudFolderName == ServerTestCase.cloudFolderName)
            XCTAssert(result[0].mimeType == mimeType)
            XCTAssert(result[0].appMetaData == appMetaData)
            XCTAssert(result[0].deleted == false)
            XCTAssert(result[0].fileVersion == fileVersionToUpload)
            XCTAssert(result[0].fileSizeBytes == fileSize)
            
            guard let downloadResponse = self.downloadTextFile(masterVersionExpectedWithDownload: Int(masterVersion + 1), appMetaData: appMetaData, downloadFileVersion: fileVersionToUpload, uploadFileRequest: uploadRequest, fileSize: fileSize), let downloadData = downloadResponse.data else {
                XCTFail()
                return
            }

            XCTAssert(uploadRequest.data == downloadData)
        }
    }
    
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
    
    @discardableResult
    // Master version after this call is sent back.
    func uploadVersion(_ version: FileVersionInt, fileUUID:String) -> MasterVersionInt {
        let appMetaData = "Some-App-Meta-Data"
        let deviceUUID1 = PerfectLib.UUID().string
        
        let (uploadRequest, _) = uploadTextFile(deviceUUID: deviceUUID1, fileUUID:fileUUID, appMetaData:appMetaData)
        // Send DoneUploads-- to commit version 0.
        sendDoneUploads(expectedNumberOfUploads: 1, deviceUUID:deviceUUID1)
        
        var fileVersion:FileVersionInt = 1
        var masterVersion:MasterVersionInt = 1
        
        for _ in 1...version {
            let deviceUUID2 = PerfectLib.UUID().string
            _ = uploadTextFile(deviceUUID: deviceUUID2, fileUUID: uploadRequest.fileUUID, addUser: false, fileVersion:fileVersion, masterVersion: masterVersion)
            sendDoneUploads(expectedNumberOfUploads: 1, deviceUUID:deviceUUID2, masterVersion: masterVersion)
            
            fileVersion += 1
            masterVersion += 1
        }
        
        return masterVersion
    }
    
    // Upload some number (e.g., 5) of new versions.
    func testSuccessiveUploadsOfNextVersionWorks() {
        let fileUUID = PerfectLib.UUID().string
        uploadVersion(5, fileUUID:fileUUID)
    }
    
    func testUploadDifferentFileContentsForSecondVersionWorks() {
        // Upload small text file first.
        let appMetaData = "Some-App-Meta-Data"
        let deviceUUID1 = PerfectLib.UUID().string
        
        let (uploadRequest, _) = uploadTextFile(deviceUUID: deviceUUID1, appMetaData:appMetaData)
        // Send DoneUploads-- to commit version 0.
        sendDoneUploads(expectedNumberOfUploads: 1, deviceUUID:deviceUUID1, masterVersion: 0)
        
        // Then upload large image file-- as version 1 of the same file.
        guard let (uploadRequest2, fileSize2) = uploadJPEGFile(deviceUUID:deviceUUID1,
            fileUUID:uploadRequest.fileUUID, addUser:false, fileVersion:1, expectedMasterVersion: 1) else {
            XCTFail()
            return
        }
        
        sendDoneUploads(expectedNumberOfUploads: 1, deviceUUID:deviceUUID1, masterVersion: 1)
        
        // Make sure the mime type changed and file contents is right.
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

            XCTAssert(result[0].mimeType == ServerTestCase.jpegMimeType)
            
            guard let downloadResponse = self.downloadTextFile(masterVersionExpectedWithDownload: 2, appMetaData: appMetaData, downloadFileVersion: 1, uploadFileRequest: uploadRequest2, fileSize: fileSize2), let downloadData = downloadResponse.data else {
                XCTFail()
                return
            }

            XCTAssert(uploadRequest2.data == downloadData)
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
        let masterVersion = uploadVersion(2, fileUUID:fileUUID)
        
        let uploadDeletionRequest = UploadDeletionRequest(json: [
            UploadDeletionRequest.fileUUIDKey: fileUUID,
            UploadDeletionRequest.fileVersionKey: 2,
            UploadDeletionRequest.masterVersionKey: masterVersion
        ])!
        
        let deviceUUID = PerfectLib.UUID().string
        uploadDeletion(uploadDeletionRequest: uploadDeletionRequest, deviceUUID: deviceUUID, addUser: false)
        sendDoneUploads(expectedNumberOfUploads: 1, deviceUUID: deviceUUID, masterVersion: masterVersion)
    }
    
#if false
    func testFileIndexReportsVariousFileVersions() {
    }
    
    // MARK: Download
    
    func testDownloadOfFileVersion1Works() {
    }
    
    func testDownloadOfBadVersionFails() {
    }
#endif
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
            ("testUploadDeletionOfVersionThatExistsWorks", testUploadDeletionOfVersionThatExistsWorks)
        ]
    }
    
    func testLinuxTestSuiteIncludesAllTests() {
        linuxTestSuiteIncludesAllTests(testType:FileController_MultiVersionFiles.self)
    }
}
