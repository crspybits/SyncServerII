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
import PerfectLib
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
    
    // Try to update from nil app data to version 1 (or other than 0).
    
    // Try to update from version N meta data to version N (or other, non N+1).

    // Attempt to upload app meta data for a deleted file.
    
    // UploadAppMetaData for a file that doesn't exist.

    // UploadAppMetaData, then use regular download to retrieve.
    // In testing for successful UploadAppMetaData calls, need to make sure the FileIndex has been changed appropriately. Make sure the deviceUUID has *not* changed due to the app meta data update.
    func testSuccessUsingDownloadToCheck() {
        var masterVersion: MasterVersionInt = 0
        let deviceUUID = PerfectLib.UUID().string
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
        let deviceUUID2 = PerfectLib.UUID().string

        // Use a different deviceUUID so we can check that the app meta data update doesn't change it in the FileIndex.
        uploadAppMetaDataVersion(deviceUUID: deviceUUID2, fileUUID: uploadRequest.fileUUID, masterVersion:masterVersion, appMetaData: appMetaData2)
        sendDoneUploads(expectedNumberOfUploads: 1, deviceUUID:deviceUUID2, masterVersion: masterVersion)
        masterVersion += 1
        
        guard let downloadAppMetaDataResponse = downloadAppMetaDataVersion(deviceUUID:deviceUUID, fileUUID: uploadRequest.fileUUID, masterVersionExpectedWithDownload:masterVersion, appMetaDataVersion: appMetaData2.version, expectedError: false) else {
            XCTFail()
            return
        }
        
        XCTAssert(downloadAppMetaDataResponse.appMetaData == appMetaData2.contents)
    
        guard let fileInfoObjs2 = getFileIndex(deviceUUID: deviceUUID), fileInfoObjs2.count == 1 else {
            XCTFail()
            return
        }
        let fileInfo2 = fileInfoObjs2[0]
        
        XCTAssert(fileInfo2.fileUUID == uploadRequest.fileUUID)
        XCTAssert(fileInfo2.deviceUUID == deviceUUID)
        
        // Updating app meta data doesn't change dates.
        XCTAssert(fileInfo2.creationDate == fileInfo1.creationDate)
        XCTAssert(fileInfo2.updateDate == fileInfo1.updateDate)
        
        XCTAssert(fileInfo2.mimeType == uploadRequest.mimeType)
        XCTAssert(fileInfo2.deleted == false)
        
        XCTAssert(fileInfo2.appMetaDataVersion == appMetaData2.version)
        XCTAssert(fileInfo2.fileVersion == 0)
        XCTAssert(fileInfo2.fileSizeBytes == fileSizeBytes)
    }
    
    // UploadAppMetaData, then use DownloadAppMetaData to retrieve.
    
    // UploadAppMetaData, of an initially nil app meta data.
    
}

extension FileController_UploadAppMetaDataTests {
    static var allTests : [(String, (FileController_UploadAppMetaDataTests) -> () throws -> Void)] {
        return [
            ("testSuccessUsingDownloadToCheck", testSuccessUsingDownloadToCheck)
        ]
    }
    
    func testLinuxTestSuiteIncludesAllTests() {
        linuxTestSuiteIncludesAllTests(testType:FileController_UploadAppMetaDataTests.self)
    }
}

