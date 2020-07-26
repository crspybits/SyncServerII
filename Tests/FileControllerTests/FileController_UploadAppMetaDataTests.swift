//
//  FileController_UploadAppMetaDataTests.swift
//  ServerTests
//
//  Created by Christopher G Prince on 3/25/18.
//

import XCTest
@testable import Server
@testable import TestsCommon
import LoggerAPI
import Foundation
import ServerShared

class FileController_UploadAppMetaDataTests: ServerTestCase, LinuxTestable {
    
    override func setUp() {
        super.setUp()
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }
    
    override func tearDown() {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
        super.tearDown()
    }

    func checkFileIndex(before: FileInfo, after: FileInfo, uploadRequest: UploadFileRequest, deviceUUID: String) {
        XCTAssert(after.fileUUID == uploadRequest.fileUUID)
        XCTAssert(after.deviceUUID == deviceUUID)
        
        // Updating app meta data doesn't change dates.
        XCTAssert(after.creationDate == before.creationDate)
        XCTAssert(after.updateDate == before.updateDate)
        
        XCTAssert(after.mimeType == uploadRequest.mimeType)
        XCTAssert(after.deleted == false)
    }
    
#if false
    func successDownloadAppMetaData(usingFileDownload: Bool) {
        var masterVersion: MasterVersionInt = 0
        let deviceUUID = Foundation.UUID().uuidString
        let appMetaData1 = "Test1"
        let testAccount:TestAccount = .primaryOwningAccount
        
        guard let uploadResult = uploadTextFile(testAccount: testAccount, deviceUUID:deviceUUID, masterVersion:masterVersion, appMetaData:appMetaData1),
            let sharingGroupUUID = uploadResult.sharingGroupUUID else {
            XCTFail()
            return
        }
        
        // sendDoneUploads(expectedNumberOfUploads: 1, deviceUUID:deviceUUID, sharingGroupUUID:sharingGroupUUID)
        masterVersion += 1
        
        guard let (files, _) = getIndex(deviceUUID: deviceUUID, sharingGroupUUID:sharingGroupUUID),
            let fileInfoObjs1 = files, fileInfoObjs1.count == 1 else {
            XCTFail()
            return
        }
        let fileInfo1 = fileInfoObjs1[0]
        
        let appMetaData2 = "Test2"
        let deviceUUID2 = Foundation.UUID().uuidString

        // Use a different deviceUUID so we can check that the app meta data update doesn't change it in the FileIndex.
        assert(false) // DEPRECATED
        //uploadAppMetaDataVersion(deviceUUID: deviceUUID2, fileUUID: uploadResult.request.fileUUID, masterVersion:masterVersion, sharingGroupUUID:sharingGroupUUID)
        // sendDoneUploads(expectedNumberOfUploads: 1, deviceUUID:deviceUUID2, sharingGroupUUID: sharingGroupUUID)
        masterVersion += 1
        
        if usingFileDownload {
            guard let downloadResponse = downloadTextFile(masterVersionExpectedWithDownload:Int(masterVersion), appMetaData:appMetaData2, uploadFileRequest:uploadResult.request) else {
                XCTFail()
                return
            }
            
            XCTAssert(downloadResponse.appMetaData == appMetaData2)
        }
        else {
            guard let downloadAppMetaDataResponse = downloadAppMetaDataVersion(deviceUUID:deviceUUID, fileUUID: uploadResult.request.fileUUID, sharingGroupUUID: sharingGroupUUID, expectedError: false) else {
                XCTFail()
                return
            }
        
            XCTAssert(downloadAppMetaDataResponse.appMetaData == appMetaData2)
        }
        
        guard let (files2, _) = getIndex(deviceUUID: deviceUUID, sharingGroupUUID:sharingGroupUUID),
            let fileInfoObjs2 = files2, fileInfoObjs2.count == 1 else {
            XCTFail()
            return
        }
        let fileInfo2 = fileInfoObjs2[0]
        
        checkFileIndex(before: fileInfo1, after: fileInfo2, uploadRequest: uploadResult.request, deviceUUID: deviceUUID)
    }
    
    func uploadAppMetaDataOfInitiallyNilAppMetaDataWorks(toAppMetaDataVersion appMetaDataVersion: AppMetaDataVersionInt, expectedError: Bool = false) {
        var masterVersion: MasterVersionInt = 0
        let deviceUUID = Foundation.UUID().uuidString
        
        guard let uploadResult = uploadTextFile(deviceUUID:deviceUUID, masterVersion:masterVersion, appMetaData:nil),
            let sharingGroupUUID = uploadResult.sharingGroupUUID else {
            XCTFail()
            return
        }
        
        // sendDoneUploads(expectedNumberOfUploads: 1, deviceUUID:deviceUUID, sharingGroupUUID: sharingGroupUUID)
        masterVersion += 1
        
        guard let (files, _) = getIndex(deviceUUID: deviceUUID, sharingGroupUUID:sharingGroupUUID), let fileInfoObjs1 = files, fileInfoObjs1.count == 1 else {
            XCTFail()
            return
        }
        let fileInfo1 = fileInfoObjs1[0]
        
        let appMetaData = AppMetaData(version: appMetaDataVersion, contents: "Test2")
        let deviceUUID2 = Foundation.UUID().uuidString

        // Use a different deviceUUID so we can check that the app meta data update doesn't change it in the FileIndex.
        uploadAppMetaDataVersion(deviceUUID: deviceUUID2, fileUUID: uploadResult.request.fileUUID, masterVersion:masterVersion, appMetaData: appMetaData, sharingGroupUUID:sharingGroupUUID, expectedError: expectedError)
        
        if !expectedError {
            // sendDoneUploads(expectedNumberOfUploads: 1, deviceUUID:deviceUUID2, sharingGroupUUID: sharingGroupUUID)
            masterVersion += 1
            
            guard let downloadAppMetaDataResponse = downloadAppMetaDataVersion(deviceUUID:deviceUUID, fileUUID: uploadResult.request.fileUUID, sharingGroupUUID: sharingGroupUUID, expectedError: false) else {
                XCTFail()
                return
            }
        
            XCTAssert(downloadAppMetaDataResponse.appMetaData == appMetaData.contents)
            
            guard let (files2, _) = getIndex(deviceUUID: deviceUUID, sharingGroupUUID:sharingGroupUUID), let fileInfoObjs2 = files2, fileInfoObjs2.count == 1 else {
                XCTFail()
                return
            }
            let fileInfo2 = fileInfoObjs2[0]
            
            checkFileIndex(before: fileInfo1, after: fileInfo2, uploadRequest: uploadResult.request, deviceUUID: deviceUUID)
        }
    }
    
    // Try to update from nil app data to version 1 (or other than 0).
    func testUploadAppMetaDataOfInitiallyNilAppMetaDataToVersion1Fails() {
        uploadAppMetaDataOfInitiallyNilAppMetaDataWorks(toAppMetaDataVersion: 1, expectedError: true)
    }
    
    // Try to update from version N meta data to version N (or other, non N+1).
    func testUpdateFromVersion0ToVersion0Fails() {
        let deviceUUID = Foundation.UUID().uuidString
        let appMetaData1 = "Test1"
        
        guard let uploadResult = uploadTextFile(deviceUUID:deviceUUID, appMetaData:appMetaData1),
            let sharingGroupUUID = uploadResult.sharingGroupUUID else {
            XCTFail()
            return
        }
        
        // sendDoneUploads(expectedNumberOfUploads: 1, deviceUUID:deviceUUID, sharingGroupUUID: sharingGroupUUID)
        
        let appMetaData2 = "Test2"

        uploadAppMetaDataVersion(deviceUUID: deviceUUID, fileUUID: uploadResult.request.fileUUID, appMetaData: appMetaData2, sharingGroupUUID: sharingGroupUUID, expectedError: true)
    }

    // Attempt to upload app meta data for a deleted file.
    func testUploadAppMetaDataForDeletedFileFails() {
        let deviceUUID = Foundation.UUID().uuidString
        var masterVersion: MasterVersionInt = 0

        guard let uploadResult = uploadTextFile(deviceUUID:deviceUUID, masterVersion: masterVersion),
            let sharingGroupUUID = uploadResult.sharingGroupUUID else {
            XCTFail()
            return
        }
        
        // sendDoneUploads(expectedNumberOfUploads: 1, deviceUUID:deviceUUID, masterVersion: masterVersion, sharingGroupUUID: sharingGroupUUID)
        masterVersion += 1
        
        let uploadDeletionRequest = UploadDeletionRequest()
        uploadDeletionRequest.fileUUID = uploadResult.request.fileUUID
        uploadDeletionRequest.fileVersion = uploadResult.request.fileVersion
        uploadDeletionRequest.masterVersion = uploadResult.request.masterVersion + MasterVersionInt(1)
        uploadDeletionRequest.sharingGroupUUID = sharingGroupUUID
        
        uploadDeletion(uploadDeletionRequest: uploadDeletionRequest, deviceUUID: deviceUUID, addUser: false)
        // sendDoneUploads(expectedNumberOfUploads: 1, deviceUUID:deviceUUID, masterVersion: masterVersion, sharingGroupUUID: sharingGroupUUID)
        masterVersion += 1
        
        let appMetaData = AppMetaData(version: 0, contents: "Test2")
        uploadAppMetaDataVersion(deviceUUID: deviceUUID, fileUUID: uploadResult.request.fileUUID, masterVersion:masterVersion, appMetaData: appMetaData, sharingGroupUUID:sharingGroupUUID, expectedError: true)
    }
    
    // UploadAppMetaData for a file that doesn't exist.
    func testUploadAppMetaDataForANonExistentFileFails() {
        let deviceUUID = Foundation.UUID().uuidString
        let masterVersion: MasterVersionInt = 0
        let appMetaData = AppMetaData(version: 0, contents: "Test1")
        let badFileUUID = Foundation.UUID().uuidString
        let cloudFolderName = ServerTestCase.cloudFolderName

        let sharingGroupUUID = Foundation.UUID().uuidString

        guard let _ = addNewUser(sharingGroupUUID: sharingGroupUUID, deviceUUID:deviceUUID, cloudFolderName: cloudFolderName) else {
            XCTFail()
            return
        }
        
        uploadAppMetaDataVersion(deviceUUID: deviceUUID, fileUUID: badFileUUID, masterVersion:masterVersion, appMetaData: appMetaData, sharingGroupUUID:sharingGroupUUID, expectedError: true)
    }
    
    // Use download file to try to download an incorrect meta data version.
    func testFileDownloadOfBadMetaDataVersionFails() {
        var masterVersion: MasterVersionInt = 0
        let deviceUUID = Foundation.UUID().uuidString
        let appMetaData1 = AppMetaData(version: 0, contents: "Test1")
        
        guard let uploadResult = uploadTextFile(deviceUUID:deviceUUID, masterVersion:masterVersion, appMetaData:appMetaData1),
            let sharingGroupUUID = uploadResult.sharingGroupUUID else {
            XCTFail()
            return
        }
        
        // sendDoneUploads(expectedNumberOfUploads: 1, deviceUUID:deviceUUID, masterVersion: masterVersion, sharingGroupUUID: sharingGroupUUID)
        masterVersion += 1
        
        let appMetaData2 = AppMetaData(version: 1, contents: "Test2")
        let deviceUUID2 = Foundation.UUID().uuidString

        // Use a different deviceUUID so we can check that the app meta data update doesn't change it in the FileIndex.
        uploadAppMetaDataVersion(deviceUUID: deviceUUID2, fileUUID: uploadResult.request.fileUUID, masterVersion:masterVersion, appMetaData: appMetaData2, sharingGroupUUID: sharingGroupUUID)
        // sendDoneUploads(expectedNumberOfUploads: 1, deviceUUID:deviceUUID2, masterVersion: masterVersion, sharingGroupUUID: sharingGroupUUID)
        masterVersion += 1

        let appMetaData3 = AppMetaData(version: appMetaData2.version + 1, contents: appMetaData2.contents)
        downloadTextFile(masterVersionExpectedWithDownload:Int(masterVersion), appMetaData:appMetaData3, uploadFileRequest:uploadResult.request, expectedError: true)
    }
    
    // UploadAppMetaData, then use regular download to retrieve.
    func testSuccessUsingFileDownloadToCheck() {
        successDownloadAppMetaData(usingFileDownload: true)
    }
    
    // UploadAppMetaData, then use DownloadAppMetaData to retrieve.
    func testSuccessUsingDownloadAppMetaDataToCheck() {
        successDownloadAppMetaData(usingFileDownload: false)
    }
    
    func testUploadAppMetaDataOfInitiallyNilAppMetaDataToVersion0Works() {
        uploadAppMetaDataOfInitiallyNilAppMetaDataWorks(toAppMetaDataVersion: 0)
    }
    
    func testUploadAppMetaDataWithFakeSharingGroupUUIDFails() {
        var masterVersion: MasterVersionInt = 0
        let deviceUUID = Foundation.UUID().uuidString
        let appMetaData1 = AppMetaData(version: 0, contents: "Test1")
        
        guard let uploadResult = uploadTextFile(deviceUUID:deviceUUID, masterVersion:masterVersion, appMetaData:appMetaData1),
            let sharingGroupUUID = uploadResult.sharingGroupUUID else {
            XCTFail()
            return
        }
        
        // sendDoneUploads(expectedNumberOfUploads: 1, deviceUUID:deviceUUID, masterVersion: masterVersion, sharingGroupUUID:sharingGroupUUID)
        masterVersion += 1
        
        guard let (files, _) = getIndex(deviceUUID: deviceUUID, sharingGroupUUID:sharingGroupUUID), let fileInfoObjs1 = files, fileInfoObjs1.count == 1 else {
            XCTFail()
            return
        }
        
        let appMetaData2 = AppMetaData(version: 1, contents: "Test2")
        let deviceUUID2 = Foundation.UUID().uuidString

        let invalidSharingGroupUUID = UUID().uuidString

        uploadAppMetaDataVersion(deviceUUID: deviceUUID2, fileUUID: uploadResult.request.fileUUID, masterVersion:masterVersion, appMetaData: appMetaData2, sharingGroupUUID:invalidSharingGroupUUID, expectedError: true)
    }
    
    func testUploadAppMetaDataWithInvalidSharingGroupUUIDFails() {
        var masterVersion: MasterVersionInt = 0
        let deviceUUID = Foundation.UUID().uuidString
        let appMetaData1 = AppMetaData(version: 0, contents: "Test1")
        
        guard let uploadResult = uploadTextFile(deviceUUID:deviceUUID, masterVersion:masterVersion, appMetaData:appMetaData1),
            let sharingGroupUUID = uploadResult.sharingGroupUUID else {
            XCTFail()
            return
        }
        
        // sendDoneUploads(expectedNumberOfUploads: 1, deviceUUID:deviceUUID, masterVersion: masterVersion, sharingGroupUUID:sharingGroupUUID)
        masterVersion += 1
        
        guard let (files, _) = getIndex(deviceUUID: deviceUUID, sharingGroupUUID:sharingGroupUUID), let fileInfoObjs1 = files, fileInfoObjs1.count == 1 else {
            XCTFail()
            return
        }
        
        let appMetaData2 = AppMetaData(version: 1, contents: "Test2")
        let deviceUUID2 = Foundation.UUID().uuidString

        let workingButBadSharingGroupUUID = UUID().uuidString
        guard addSharingGroup(sharingGroupUUID: workingButBadSharingGroupUUID) else {
            XCTFail()
            return
        }

        uploadAppMetaDataVersion(deviceUUID: deviceUUID2, fileUUID: uploadResult.request.fileUUID, masterVersion:masterVersion, appMetaData: appMetaData2, sharingGroupUUID:workingButBadSharingGroupUUID, expectedError: true)
    }
#endif
}

extension FileController_UploadAppMetaDataTests {
    static var allTests : [(String, (FileController_UploadAppMetaDataTests) -> () throws -> Void)] {
        return [
        /*
            ("testUploadAppMetaDataOfInitiallyNilAppMetaDataToVersion1Fails", testUploadAppMetaDataOfInitiallyNilAppMetaDataToVersion1Fails),
            ("testUpdateFromVersion0ToVersion0Fails", testUpdateFromVersion0ToVersion0Fails),
            ("testUploadAppMetaDataForDeletedFileFails", testUploadAppMetaDataForDeletedFileFails),
            ("testUploadAppMetaDataForANonExistentFileFails", testUploadAppMetaDataForANonExistentFileFails),
            ("testFileDownloadOfBadMetaDataVersionFails", testFileDownloadOfBadMetaDataVersionFails),
            ("testSuccessUsingFileDownloadToCheck", testSuccessUsingFileDownloadToCheck),
            ("testSuccessUsingDownloadAppMetaDataToCheck", testSuccessUsingDownloadAppMetaDataToCheck),
            ("testUploadAppMetaDataOfInitiallyNilAppMetaDataToVersion0Works", testUploadAppMetaDataOfInitiallyNilAppMetaDataToVersion0Works),
            ("testUploadAppMetaDataWithInvalidSharingGroupUUIDFails", testUploadAppMetaDataWithInvalidSharingGroupUUIDFails),
            ("testUploadAppMetaDataWithFakeSharingGroupUUIDFails", testUploadAppMetaDataWithFakeSharingGroupUUIDFails)
            */
        ]
    }
    
    func testLinuxTestSuiteIncludesAllTests() {
        linuxTestSuiteIncludesAllTests(testType:FileController_UploadAppMetaDataTests.self)
    }
}

