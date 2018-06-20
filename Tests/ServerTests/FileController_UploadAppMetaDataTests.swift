//
//  FileController_UploadAppMetaDataTests.swift
//  ServerTests
//
//  Created by Christopher G Prince on 3/25/18.
//

import XCTest
@testable import Server
import LoggerAPI
import Foundation
import SyncServerShared

class FileController_UploadAppMetaDataTests: ServerTestCase, LinuxTestable {
    
    override func setUp() {
        super.setUp()
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }
    
    override func tearDown() {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
        super.tearDown()
    }
    
    @discardableResult
    func uploadAppMetaDataVersion(testAccount:TestAccount = .primaryOwningAccount, deviceUUID: String, fileUUID: String, masterVersion:Int64, appMetaData: AppMetaData, expectedError: Bool = false) -> UploadAppMetaDataResponse? {

        var result:UploadAppMetaDataResponse?
        
        self.performServerTest(testAccount:testAccount) { expectation, testCreds in
            let headers = self.setupHeaders(testUser:testAccount, accessToken: testCreds.accessToken, deviceUUID:deviceUUID)

            let uploadAppMetaDataRequest = UploadAppMetaDataRequest()
            uploadAppMetaDataRequest.fileUUID = fileUUID
            uploadAppMetaDataRequest.masterVersion = masterVersion
            uploadAppMetaDataRequest.appMetaData = appMetaData
            
            self.performRequest(route: ServerEndpoints.uploadAppMetaData, headers: headers, urlParameters: "?" + uploadAppMetaDataRequest.urlParameters()!, body:nil) { response, dict in
                Log.info("Status code: \(response!.statusCode)")
                
                if expectedError {
                    XCTAssert(response!.statusCode != .OK, "Did not work on failing uploadAppMetaDataRequest request")
                }
                else {
                    XCTAssert(response!.statusCode == .OK, "Did not work on uploadAppMetaDataRequest request")
                    
                    if let dict = dict,
                        let uploadAppMetaDataResponse = UploadAppMetaDataResponse(json: dict) {
                        if uploadAppMetaDataResponse.masterVersionUpdate == nil {
                            result = uploadAppMetaDataResponse
                        }
                        else {
                            XCTFail()
                        }
                    }
                    else {
                        XCTFail()
                    }
                }
                
                expectation.fulfill()
            }
        }
        
        return result
    }
    
    func checkFileIndex(before: FileInfo, after: FileInfo, uploadRequest: UploadFileRequest, deviceUUID: String, fileVersion: FileVersionInt, fileSizeBytes: Int64, appMetaDataVersion: AppMetaDataVersionInt) {
        XCTAssert(after.fileUUID == uploadRequest.fileUUID)
        XCTAssert(after.deviceUUID == deviceUUID)
        
        // Updating app meta data doesn't change dates.
        XCTAssert(after.creationDate == before.creationDate)
        XCTAssert(after.updateDate == before.updateDate)
        
        XCTAssert(after.mimeType == uploadRequest.mimeType)
        XCTAssert(after.deleted == false)
        
        XCTAssert(after.appMetaDataVersion == appMetaDataVersion)
        XCTAssert(after.fileVersion == fileVersion)
        XCTAssert(after.fileSizeBytes == fileSizeBytes)
    }
    
    func successDownloadAppMetaData(usingFileDownload: Bool) {
        var masterVersion: MasterVersionInt = 0
        let deviceUUID = Foundation.UUID().uuidString
        let appMetaData1 = AppMetaData(version: 0, contents: "Test1")
        
        let (uploadRequest, fileSizeBytes) = uploadTextFile(deviceUUID:deviceUUID, masterVersion:masterVersion, appMetaData:appMetaData1)
        sendDoneUploads(expectedNumberOfUploads: 1, deviceUUID:deviceUUID, masterVersion: masterVersion)
        masterVersion += 1
        
        guard let fileInfoObjs1 = getFileIndex(deviceUUID: deviceUUID), fileInfoObjs1.count == 1 else {
            XCTFail()
            return
        }
        let fileInfo1 = fileInfoObjs1[0]
        
        let appMetaData2 = AppMetaData(version: 1, contents: "Test2")
        let deviceUUID2 = Foundation.UUID().uuidString

        // Use a different deviceUUID so we can check that the app meta data update doesn't change it in the FileIndex.
        uploadAppMetaDataVersion(deviceUUID: deviceUUID2, fileUUID: uploadRequest.fileUUID, masterVersion:masterVersion, appMetaData: appMetaData2)
        sendDoneUploads(expectedNumberOfUploads: 1, deviceUUID:deviceUUID2, masterVersion: masterVersion)
        masterVersion += 1
        
        if usingFileDownload {
            guard let downloadResponse = downloadTextFile(masterVersionExpectedWithDownload:Int(masterVersion), appMetaData:appMetaData2, uploadFileRequest:uploadRequest, fileSize:fileSizeBytes) else {
                XCTFail()
                return
            }
            
            XCTAssert(downloadResponse.appMetaData == appMetaData2.contents)
        }
        else {
            guard let downloadAppMetaDataResponse = downloadAppMetaDataVersion(deviceUUID:deviceUUID, fileUUID: uploadRequest.fileUUID, masterVersionExpectedWithDownload:masterVersion, appMetaDataVersion: appMetaData2.version, expectedError: false) else {
                XCTFail()
                return
            }
        
            XCTAssert(downloadAppMetaDataResponse.appMetaData == appMetaData2.contents)
        }
        
        guard let fileInfoObjs2 = getFileIndex(deviceUUID: deviceUUID), fileInfoObjs2.count == 1 else {
            XCTFail()
            return
        }
        let fileInfo2 = fileInfoObjs2[0]
        
        checkFileIndex(before: fileInfo1, after: fileInfo2, uploadRequest: uploadRequest, deviceUUID: deviceUUID, fileVersion: 0, fileSizeBytes: fileSizeBytes, appMetaDataVersion: appMetaData2.version)
    }
    
    func uploadAppMetaDataOfInitiallyNilAppMetaDataWorks(toAppMetaDataVersion appMetaDataVersion: AppMetaDataVersionInt, expectedError: Bool = false) {
        var masterVersion: MasterVersionInt = 0
        let deviceUUID = Foundation.UUID().uuidString
        
        let (uploadRequest, fileSizeBytes) = uploadTextFile(deviceUUID:deviceUUID, masterVersion:masterVersion, appMetaData:nil)
        sendDoneUploads(expectedNumberOfUploads: 1, deviceUUID:deviceUUID, masterVersion: masterVersion)
        masterVersion += 1
        
        guard let fileInfoObjs1 = getFileIndex(deviceUUID: deviceUUID), fileInfoObjs1.count == 1 else {
            XCTFail()
            return
        }
        let fileInfo1 = fileInfoObjs1[0]
        
        let appMetaData = AppMetaData(version: appMetaDataVersion, contents: "Test2")
        let deviceUUID2 = Foundation.UUID().uuidString

        // Use a different deviceUUID so we can check that the app meta data update doesn't change it in the FileIndex.
        uploadAppMetaDataVersion(deviceUUID: deviceUUID2, fileUUID: uploadRequest.fileUUID, masterVersion:masterVersion, appMetaData: appMetaData, expectedError: expectedError)
        
        if !expectedError {
            sendDoneUploads(expectedNumberOfUploads: 1, deviceUUID:deviceUUID2, masterVersion: masterVersion)
            masterVersion += 1
            
            guard let downloadAppMetaDataResponse = downloadAppMetaDataVersion(deviceUUID:deviceUUID, fileUUID: uploadRequest.fileUUID, masterVersionExpectedWithDownload:masterVersion, appMetaDataVersion: appMetaData.version, expectedError: false) else {
                XCTFail()
                return
            }
        
            XCTAssert(downloadAppMetaDataResponse.appMetaData == appMetaData.contents)
            
            guard let fileInfoObjs2 = getFileIndex(deviceUUID: deviceUUID), fileInfoObjs2.count == 1 else {
                XCTFail()
                return
            }
            let fileInfo2 = fileInfoObjs2[0]
            
            checkFileIndex(before: fileInfo1, after: fileInfo2, uploadRequest: uploadRequest, deviceUUID: deviceUUID, fileVersion: 0, fileSizeBytes: fileSizeBytes, appMetaDataVersion: appMetaData.version)
        }
    }
    
    // Try to update from nil app data to version 1 (or other than 0).
    func testUploadAppMetaDataOfInitiallyNilAppMetaDataToVersion1Fails() {
        uploadAppMetaDataOfInitiallyNilAppMetaDataWorks(toAppMetaDataVersion: 1, expectedError: true)
    }
    
    // Try to update from version N meta data to version N (or other, non N+1).
    func testUpdateFromVersion0ToVersion0Fails() {
        var masterVersion: MasterVersionInt = 0
        let deviceUUID = Foundation.UUID().uuidString
        let appMetaData1 = AppMetaData(version: 0, contents: "Test1")
        
        let (uploadRequest, _) = uploadTextFile(deviceUUID:deviceUUID, masterVersion:masterVersion, appMetaData:appMetaData1)
        sendDoneUploads(expectedNumberOfUploads: 1, deviceUUID:deviceUUID, masterVersion: masterVersion)
        masterVersion += 1
        
        let appMetaData2 = AppMetaData(version: 0, contents: "Test2")

        uploadAppMetaDataVersion(deviceUUID: deviceUUID, fileUUID: uploadRequest.fileUUID, masterVersion:masterVersion, appMetaData: appMetaData2, expectedError: true)
    }

    // Attempt to upload app meta data for a deleted file.
    func testUploadAppMetaDataForDeletedFileFails() {
        let deviceUUID = Foundation.UUID().uuidString
        var masterVersion: MasterVersionInt = 0

        let (uploadRequest, _) = uploadTextFile(deviceUUID:deviceUUID, masterVersion: masterVersion)
        sendDoneUploads(expectedNumberOfUploads: 1, deviceUUID:deviceUUID, masterVersion: masterVersion)
        masterVersion += 1
        
        let uploadDeletionRequest = UploadDeletionRequest(json: [
            UploadDeletionRequest.fileUUIDKey: uploadRequest.fileUUID,
            UploadDeletionRequest.fileVersionKey: uploadRequest.fileVersion,
            UploadDeletionRequest.masterVersionKey: uploadRequest.masterVersion + MasterVersionInt(1)
        ])!
        
        uploadDeletion(uploadDeletionRequest: uploadDeletionRequest, deviceUUID: deviceUUID, addUser: false)
        sendDoneUploads(expectedNumberOfUploads: 1, deviceUUID:deviceUUID, masterVersion: masterVersion)
        masterVersion += 1
        
        let appMetaData = AppMetaData(version: 0, contents: "Test2")
        uploadAppMetaDataVersion(deviceUUID: deviceUUID, fileUUID: uploadRequest.fileUUID, masterVersion:masterVersion, appMetaData: appMetaData, expectedError: true)
    }
    
    // UploadAppMetaData for a file that doesn't exist.
    func testUploadAppMetaDataForANonExistentFileFails() {
        let deviceUUID = Foundation.UUID().uuidString
        let masterVersion: MasterVersionInt = 0
        let appMetaData = AppMetaData(version: 0, contents: "Test1")
        let badFileUUID = Foundation.UUID().uuidString
        let cloudFolderName = ServerTestCase.cloudFolderName

        addNewUser(deviceUUID:deviceUUID, cloudFolderName: cloudFolderName)
        uploadAppMetaDataVersion(deviceUUID: deviceUUID, fileUUID: badFileUUID, masterVersion:masterVersion, appMetaData: appMetaData, expectedError: true)
    }
    
    // Use download file to try to download an incorrect meta data version.
    func testFileDownloadOfBadMetaDataVersionFails() {
        var masterVersion: MasterVersionInt = 0
        let deviceUUID = Foundation.UUID().uuidString
        let appMetaData1 = AppMetaData(version: 0, contents: "Test1")
        
        let (uploadRequest, fileSizeBytes) = uploadTextFile(deviceUUID:deviceUUID, masterVersion:masterVersion, appMetaData:appMetaData1)
        sendDoneUploads(expectedNumberOfUploads: 1, deviceUUID:deviceUUID, masterVersion: masterVersion)
        masterVersion += 1
        
        let appMetaData2 = AppMetaData(version: 1, contents: "Test2")
        let deviceUUID2 = Foundation.UUID().uuidString

        // Use a different deviceUUID so we can check that the app meta data update doesn't change it in the FileIndex.
        uploadAppMetaDataVersion(deviceUUID: deviceUUID2, fileUUID: uploadRequest.fileUUID, masterVersion:masterVersion, appMetaData: appMetaData2)
        sendDoneUploads(expectedNumberOfUploads: 1, deviceUUID:deviceUUID2, masterVersion: masterVersion)
        masterVersion += 1
        
        let appMetaData3 = AppMetaData(version: appMetaData2.version + 1, contents: appMetaData2.contents)
        downloadTextFile(masterVersionExpectedWithDownload:Int(masterVersion), appMetaData:appMetaData3, uploadFileRequest:uploadRequest, fileSize:fileSizeBytes, expectedError: true)
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
}

extension FileController_UploadAppMetaDataTests {
    static var allTests : [(String, (FileController_UploadAppMetaDataTests) -> () throws -> Void)] {
        return [
            ("testUploadAppMetaDataOfInitiallyNilAppMetaDataToVersion1Fails", testUploadAppMetaDataOfInitiallyNilAppMetaDataToVersion1Fails),
            ("testUpdateFromVersion0ToVersion0Fails", testUpdateFromVersion0ToVersion0Fails),
            ("testUploadAppMetaDataForDeletedFileFails", testUploadAppMetaDataForDeletedFileFails),
            ("testUploadAppMetaDataForANonExistentFileFails", testUploadAppMetaDataForANonExistentFileFails),
            ("testFileDownloadOfBadMetaDataVersionFails", testFileDownloadOfBadMetaDataVersionFails),
            ("testSuccessUsingFileDownloadToCheck", testSuccessUsingFileDownloadToCheck),
            ("testSuccessUsingDownloadAppMetaDataToCheck", testSuccessUsingDownloadAppMetaDataToCheck),
            ("testUploadAppMetaDataOfInitiallyNilAppMetaDataToVersion0Works", testUploadAppMetaDataOfInitiallyNilAppMetaDataToVersion0Works)
        ]
    }
    
    func testLinuxTestSuiteIncludesAllTests() {
        linuxTestSuiteIncludesAllTests(testType:FileController_UploadAppMetaDataTests.self)
    }
}

