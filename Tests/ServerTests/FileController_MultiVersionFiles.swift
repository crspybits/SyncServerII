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

    func uploadNextFileVersion(uploadRequest: UploadFileRequest, masterVersion: MasterVersionInt, fileVersionToUpload:FileVersionInt, creationDate: Date, mimeType: String, appMetaData: AppMetaData, checkSum:String) {
    
        guard let healthCheck1 = healthCheck() else {
            XCTFail()
            return
        }
        
        // The use of a different device UUID here is part of this test-- that the second version can be uploaded with a different device UUID.
        let deviceUUID = Foundation.UUID().uuidString
        
        guard let uploadResult1 = uploadTextFile(deviceUUID: deviceUUID, fileUUID: uploadRequest.fileUUID, addUser: .no(sharingGroupUUID: uploadRequest.sharingGroupUUID), fileVersion:fileVersionToUpload, masterVersion: masterVersion, appMetaData: appMetaData), let sharingGroupUUID = uploadResult1.sharingGroupUUID else {
            XCTFail()
            return
        }
        
        sendDoneUploads(expectedNumberOfUploads: 1, deviceUUID:deviceUUID, masterVersion: masterVersion, sharingGroupUUID: sharingGroupUUID)
        
        guard let healthCheck2 = healthCheck() else {
            XCTFail()
            return
        }
        
        // New upload device UUID will go into the FileIndex as that of the new uploading device.
        guard let (files, _) = getIndex(deviceUUID: deviceUUID, sharingGroupUUID: sharingGroupUUID),
            let fileInfoArray = files,
            fileInfoArray.count == 1 else {
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
        XCTAssert(result[0].deleted == false)
        XCTAssert(result[0].fileVersion == fileVersionToUpload)
        XCTAssert(result[0].lastUploadedCheckSum == checkSum)
        
        
        guard let _ = self.downloadTextFile(masterVersionExpectedWithDownload: Int(masterVersion + 1), appMetaData: appMetaData, downloadFileVersion: fileVersionToUpload, uploadFileRequest: uploadRequest) else {
            XCTFail()
            return
        }
    }
    
    // Also tests to make sure a different device UUID can upload the second version.
    func testUploadVersion1AfterVersion0Works() {
        let mimeType = "text/plain"
        let fileVersion:FileVersionInt = 1
        let deviceUUID1 = Foundation.UUID().uuidString
        var appMetaDataVersion: AppMetaDataVersionInt = 0
        
        guard let uploadResult = uploadTextFile(deviceUUID: deviceUUID1, appMetaData: AppMetaData(version: 0, contents: "Some-App-Meta-Data")),
            let sharingGroupUUID = uploadResult.sharingGroupUUID else {
            XCTFail()
            return
        }
        
        // Send DoneUploads-- to commit version 0.
        sendDoneUploads(expectedNumberOfUploads: 1, deviceUUID:deviceUUID1, sharingGroupUUID: sharingGroupUUID)
        appMetaDataVersion += 1
        
        var creationDate:Date!
        
        guard let (files, _) = getIndex(deviceUUID: deviceUUID1, sharingGroupUUID: sharingGroupUUID), let fileInfoArray = files, fileInfoArray.count == 1 else {
            XCTFail()
            return
        }
        
        creationDate = fileInfoArray[0].creationDate
        
        guard creationDate != nil else {
            XCTFail()
            return
        }
        
        uploadNextFileVersion(uploadRequest: uploadResult.request, masterVersion: 1, fileVersionToUpload:fileVersion, creationDate: creationDate!, mimeType: mimeType, appMetaData: AppMetaData(version: 1, contents: "Some-Other-App-Meta-Data"), checkSum:uploadResult.checkSum)
    }
    
    // Attempt to upload version 1 when version 0 hasn't yet been committed with DoneUploads-- should fail.
    func testUploadVersion1WhenVersion0HasNotBeenCommitted() {
        let deviceUUID1 = Foundation.UUID().uuidString
        guard let uploadResult = uploadTextFile(deviceUUID: deviceUUID1), let sharingGroupUUID = uploadResult.sharingGroupUUID else {
            XCTFail()
            return
        }
        
        let deviceUUID2 = Foundation.UUID().uuidString

        uploadTextFile(deviceUUID: deviceUUID2, fileUUID: uploadResult.request.fileUUID, addUser: .no(sharingGroupUUID: sharingGroupUUID), fileVersion:1, masterVersion: 0, errorExpected: true)
    }

    // Upload version N of a file; do DoneUploads. Then try again to upload version N. That should fail.
    func testUploadOfSameFileVersionFails() {
        let deviceUUID1 = Foundation.UUID().uuidString
        
        guard let uploadResult = uploadTextFile(deviceUUID: deviceUUID1),
            let sharingGroupUUID = uploadResult.sharingGroupUUID else {
            XCTFail()
            return
        }
        
        // Send DoneUploads-- to commit version 0.
        sendDoneUploads(expectedNumberOfUploads: 1, deviceUUID:deviceUUID1, sharingGroupUUID: sharingGroupUUID)
        
        let deviceUUID2 = Foundation.UUID().uuidString

        uploadTextFile(deviceUUID: deviceUUID2, fileUUID: uploadResult.request.fileUUID, addUser: .no(sharingGroupUUID: sharingGroupUUID), fileVersion:0, masterVersion: 1, errorExpected: true)
        
        guard let (files, _) = getIndex(deviceUUID: deviceUUID1, sharingGroupUUID: sharingGroupUUID), let fileInfoArray = files, fileInfoArray.count == 1 else {
            XCTFail()
            return
        }
        
        let result = fileInfoArray.filter({$0.fileUUID == uploadResult.request.fileUUID})
        guard result.count == 1 else {
            XCTFail()
            return
        }
        
        XCTAssert(result[0].deviceUUID == deviceUUID1)
        XCTAssert(result[0].fileVersion == 0)
    }

    func testUploadVersion1OfNewFileFails() {
        _ = uploadTextFile(fileVersion:1, errorExpected: true)
    }
    
    let appMetaData = "Some-App-Meta-Data"
    
    @discardableResult
    // Master version after this call is sent back.
    func uploadVersion(_ version: FileVersionInt, deviceUUID:String = Foundation.UUID().uuidString, fileUUID:String, startMasterVersion: MasterVersionInt = 0, addUser:AddUser = .yes) -> (MasterVersionInt, UploadFileRequest)? {
        
        var masterVersion:MasterVersionInt = startMasterVersion

        guard let uploadResult = uploadTextFile(deviceUUID: deviceUUID, fileUUID:fileUUID, addUser:addUser, masterVersion:masterVersion, appMetaData:AppMetaData(version: 0, contents: appMetaData)),
            let sharingGroupUUID = uploadResult.sharingGroupUUID else {
            XCTFail()
            return nil
        }
        
        // Send DoneUploads-- to commit version 0.
        sendDoneUploads(expectedNumberOfUploads: 1, deviceUUID:deviceUUID, masterVersion:masterVersion, sharingGroupUUID: sharingGroupUUID)
        
        masterVersion += 1
        var fileVersion:FileVersionInt = 1

        for _ in 1...version {
            guard let _ = uploadTextFile(deviceUUID: deviceUUID, fileUUID: uploadResult.request.fileUUID, addUser: .no(sharingGroupUUID: sharingGroupUUID), fileVersion:fileVersion, masterVersion: masterVersion) else {
                XCTFail()
                return nil
            }
            sendDoneUploads(expectedNumberOfUploads: 1, deviceUUID:deviceUUID, masterVersion: masterVersion, sharingGroupUUID: sharingGroupUUID)
            
            fileVersion += 1
            masterVersion += 1
        }
        
        return (masterVersion, uploadResult.request)
    }
    
    // Upload some number (e.g., 5) of new versions.
    func testSuccessiveUploadsOfNextVersionWorks() {
        let fileUUID = Foundation.UUID().uuidString
        uploadVersion(5, fileUUID:fileUUID)
    }
    
    func testUploadDifferentFileContentsForSecondVersionWorks() {
        // Upload small text file first.
        let deviceUUID1 = Foundation.UUID().uuidString
        
        guard let uploadResult1 = uploadTextFile(deviceUUID: deviceUUID1, appMetaData:AppMetaData(version: 0, contents: appMetaData)),
            let sharingGroupUUID = uploadResult1.sharingGroupUUID else {
            XCTFail()
            return
        }
        
        // Send DoneUploads-- to commit version 0.
        sendDoneUploads(expectedNumberOfUploads: 1, deviceUUID:deviceUUID1, masterVersion: 0, sharingGroupUUID: sharingGroupUUID)
        
        // Then upload some other text contents -- as version 1 of the same file.
        let appMetaData2 = AppMetaData(version: 1, contents: appMetaData)
        guard let uploadResult2 = uploadTextFile(deviceUUID: deviceUUID1, fileUUID:uploadResult1.request.fileUUID, addUser: .no(sharingGroupUUID: sharingGroupUUID), fileVersion: 1, masterVersion: 1, appMetaData:appMetaData2, stringFile: TestFile.test2) else {
            XCTFail()
            return
        }
        
        sendDoneUploads(expectedNumberOfUploads: 1, deviceUUID:deviceUUID1, masterVersion: 1, sharingGroupUUID: sharingGroupUUID)
        
        // Make sure the file contents are right.
        guard let (files, _) = getIndex(deviceUUID: deviceUUID1, sharingGroupUUID: sharingGroupUUID), let fileInfoArray = files, fileInfoArray.count == 1 else {
            XCTFail()
            return
        }
        
        let result = fileInfoArray.filter({$0.fileUUID == uploadResult1.request.fileUUID})
        guard result.count == 1 else {
            XCTFail()
            return
        }
        
        guard let _ = self.downloadTextFile(masterVersionExpectedWithDownload: 2, appMetaData: appMetaData2, downloadFileVersion: 1, uploadFileRequest: uploadResult2.request) else {
            XCTFail()
            return
        }
    }
    
    // Next version uploaded must be +1
    func testUploadOfVersion2OfVersion0FileFails() {
        let deviceUUID1 = Foundation.UUID().uuidString
        guard let uploadResult = uploadTextFile(deviceUUID: deviceUUID1),
            let sharingGroupUUID = uploadResult.sharingGroupUUID else {
            XCTFail()
            return
        }
        
        // Send DoneUploads-- to commit version 0.
        sendDoneUploads(expectedNumberOfUploads: 1, deviceUUID:deviceUUID1, sharingGroupUUID: sharingGroupUUID)
        
        let deviceUUID2 = Foundation.UUID().uuidString
        guard let _ = uploadTextFile(deviceUUID: deviceUUID2, fileUUID: uploadResult.request.fileUUID, addUser: .no(sharingGroupUUID: sharingGroupUUID), fileVersion:2, masterVersion: 1, errorExpected: true) else {
            XCTFail()
            return
        }
    }
    
    // Next version uploaded must have the same mimeType
    func testUploadDifferentVersionWithDifferentMimeTypeFails() {
        let deviceUUID1 = Foundation.UUID().uuidString
        guard let uploadResult = uploadTextFile(deviceUUID: deviceUUID1),
            let sharingGroupUUID = uploadResult.sharingGroupUUID else {
            XCTFail()
            return
        }
        
        // Send DoneUploads-- to commit version 0.
        sendDoneUploads(expectedNumberOfUploads: 1, deviceUUID:deviceUUID1, sharingGroupUUID: sharingGroupUUID)
        
        guard let _ = uploadJPEGFile(deviceUUID:deviceUUID1, fileUUID: uploadResult.request.fileUUID, addUser:.no(sharingGroupUUID: sharingGroupUUID), fileVersion:1, expectedMasterVersion:1, errorExpected: true) else {
            XCTFail()
            return
        }
    }
    
    func testUploadOfTwoConsecutiveVersionsWithoutADoneUploadsAfterVersion0IsUploadedFails() {
        let deviceUUID1 = Foundation.UUID().uuidString
        
        guard let uploadResult = uploadTextFile(deviceUUID:deviceUUID1),
            let sharingGroupUUID = uploadResult.sharingGroupUUID else {
            XCTFail()
            return
        }
        
        // Send DoneUploads-- to commit version 0.
        sendDoneUploads(expectedNumberOfUploads: 1, deviceUUID:deviceUUID1, sharingGroupUUID: sharingGroupUUID)
        
        let deviceUUID2 = Foundation.UUID().uuidString
        guard let _ = uploadTextFile(deviceUUID: deviceUUID2, fileUUID: uploadResult.request.fileUUID, addUser: .no(sharingGroupUUID: sharingGroupUUID), fileVersion:1, masterVersion: 1, errorExpected: false) else {
            XCTFail()
            return
        }

        guard let _ = uploadTextFile(deviceUUID: deviceUUID2, fileUUID: uploadResult.request.fileUUID, addUser: .no(sharingGroupUUID: sharingGroupUUID), fileVersion:2, masterVersion: 1, errorExpected: true) else {
            XCTFail()
            return
        }
    }
    
    // MARK: Upload deletion.

    // Upload version 0. Try to delete version 1.
    func testUploadDeletionOfVersionThatDoesNotExistFails() {
        let deviceUUID1 = Foundation.UUID().uuidString
        guard let uploadResult = uploadTextFile(deviceUUID: deviceUUID1),
            let sharingGroupUUID = uploadResult.sharingGroupUUID else {
            XCTFail()
            return
        }
        
        // Send DoneUploads-- to commit version 0.
        sendDoneUploads(expectedNumberOfUploads: 1, deviceUUID:deviceUUID1, sharingGroupUUID: sharingGroupUUID)

        let uploadDeletionRequest = UploadDeletionRequest(json: [
            UploadDeletionRequest.fileUUIDKey: uploadResult.request.fileUUID,
            UploadDeletionRequest.fileVersionKey: uploadResult.request.fileVersion + 1,
            UploadDeletionRequest.masterVersionKey: uploadResult.request.masterVersion + MasterVersionInt(1),
            ServerEndpoint.sharingGroupUUIDKey: sharingGroupUUID
        ])!
        
        uploadDeletion(uploadDeletionRequest: uploadDeletionRequest, deviceUUID: deviceUUID1, addUser: false, expectError: true)
    }
    
    func testUploadDeletionOfVersionThatExistsWorks() {
        let fileUUID = Foundation.UUID().uuidString
        guard let (masterVersion, uploadRequest) = uploadVersion(2, fileUUID:fileUUID) else {
            XCTFail()
            return
        }
        
        let uploadDeletionRequest = UploadDeletionRequest(json: [
            UploadDeletionRequest.fileUUIDKey: fileUUID,
            UploadDeletionRequest.fileVersionKey: 2,
            UploadDeletionRequest.masterVersionKey: masterVersion,
            ServerEndpoint.sharingGroupUUIDKey: uploadRequest.sharingGroupUUID
        ])!
        
        let deviceUUID = Foundation.UUID().uuidString
        uploadDeletion(uploadDeletionRequest: uploadDeletionRequest, deviceUUID: deviceUUID, addUser: false)
        sendDoneUploads(expectedNumberOfUploads: 1, deviceUUID: deviceUUID, masterVersion: masterVersion, sharingGroupUUID: uploadRequest.sharingGroupUUID)
    }
    
    func checkFileIndex(deviceUUID:String, fileUUID:String, fileVersion:Int32, sharingGroupUUID: String) {
        guard let (files, _) = getIndex(deviceUUID: deviceUUID, sharingGroupUUID: sharingGroupUUID), let fileInfoArray = files else {
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
    
    // MARK: File Index

    func testFileIndexReportsVariousFileVersions() {
        let fileUUID1 = Foundation.UUID().uuidString
        let fileUUID2 = Foundation.UUID().uuidString
        let fileUUID3 = Foundation.UUID().uuidString
        let deviceUUID = Foundation.UUID().uuidString

        guard let (masterVersion, uploadRequest) = uploadVersion(2, deviceUUID: deviceUUID, fileUUID:fileUUID1),
            let sharingGroupUUID = uploadRequest.sharingGroupUUID else {
            XCTFail()
            return
        }
        
        guard let (masterVersion2, _) = uploadVersion(3, deviceUUID: deviceUUID, fileUUID:fileUUID2, startMasterVersion: masterVersion, addUser: .no(sharingGroupUUID: sharingGroupUUID)) else {
            XCTFail()
            return
        }
        
        guard let _ = uploadVersion(5, deviceUUID: deviceUUID, fileUUID:fileUUID3, startMasterVersion: masterVersion2, addUser: .no(sharingGroupUUID: sharingGroupUUID)) else {
            XCTFail()
            return
        }

        checkFileIndex(deviceUUID:deviceUUID, fileUUID:fileUUID1, fileVersion:2, sharingGroupUUID: sharingGroupUUID)
        checkFileIndex(deviceUUID:deviceUUID, fileUUID:fileUUID2, fileVersion:3, sharingGroupUUID: sharingGroupUUID)
        checkFileIndex(deviceUUID:deviceUUID, fileUUID:fileUUID3, fileVersion:5, sharingGroupUUID: sharingGroupUUID)
    }
    
    // MARK: Download
    
    func testDownloadOfFileVersion3Works() {
        let fileUUID1 = Foundation.UUID().uuidString
        let deviceUUID = Foundation.UUID().uuidString
        let fileVersion:FileVersionInt = 3
        guard let (masterVersion, uploadRequest) = uploadVersion(fileVersion, deviceUUID: deviceUUID, fileUUID:fileUUID1) else {
            XCTFail()
            return
        }
        
        let appMetaData = AppMetaData(version: 0, contents: self.appMetaData)
        guard let _ = downloadTextFile(masterVersionExpectedWithDownload: Int(masterVersion), appMetaData: appMetaData, downloadFileVersion: fileVersion, uploadFileRequest: uploadRequest) else {
            XCTFail()
            return
        }
    }
    
    func testDownloadOfBadVersionFails() {
        let fileUUID1 = Foundation.UUID().uuidString
        let deviceUUID = Foundation.UUID().uuidString
        let fileVersion:FileVersionInt = 3
        guard let (masterVersion, uploadRequest) = uploadVersion(fileVersion, deviceUUID: deviceUUID, fileUUID:fileUUID1) else {
            XCTFail()
            return
        }
        
        let appMetaData = AppMetaData(version: 0, contents: self.appMetaData)
        downloadTextFile(masterVersionExpectedWithDownload: Int(masterVersion), appMetaData: appMetaData, downloadFileVersion: fileVersion+1, uploadFileRequest: uploadRequest, expectedError: true)
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
            ("testDownloadOfBadVersionFails", testDownloadOfBadVersionFails),
            ("testUploadDifferentVersionWithDifferentMimeTypeFails", testUploadDifferentVersionWithDifferentMimeTypeFails)
        ]
    }
    
    func testLinuxTestSuiteIncludesAllTests() {
        linuxTestSuiteIncludesAllTests(testType:FileController_MultiVersionFiles.self)
    }
}
