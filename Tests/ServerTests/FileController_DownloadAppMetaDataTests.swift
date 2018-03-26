//
//  FileController_DownloadAppMetaDataTests.swift
//  ServerTests
//
//  Created by Christopher G Prince on 3/24/18.
//

import XCTest
@testable import Server
import LoggerAPI
import Foundation
import PerfectLib
import SyncServerShared

class FileController_DownloadAppMetaDataTests: ServerTestCase, LinuxTestable {
    
    override func setUp() {
        super.setUp()
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }
    
    override func tearDown() {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
        super.tearDown()
    }
    
    @discardableResult
    func downloadAppMetaDataVersion(testAccount:TestAccount = .primaryOwningAccount, deviceUUID: String, fileUUID: String, masterVersionExpectedWithDownload:Int64, expectUpdatedMasterUpdate:Bool = false, appMetaDataVersion: AppMetaDataVersionInt? = nil, expectedError: Bool = false) -> DownloadAppMetaDataResponse? {

        var result:DownloadAppMetaDataResponse?
        
        self.performServerTest(testAccount:testAccount) { expectation, testCreds in
            let headers = self.setupHeaders(testUser:testAccount, accessToken: testCreds.accessToken, deviceUUID:deviceUUID)

            let downloadAppMetaDataRequest = DownloadAppMetaDataRequest(json: [
                DownloadAppMetaDataRequest.fileUUIDKey: fileUUID,
                DownloadAppMetaDataRequest.masterVersionKey : "\(masterVersionExpectedWithDownload)",
                DownloadAppMetaDataRequest.appMetaDataVersionKey: appMetaDataVersion as Any
            ])
            
            if downloadAppMetaDataRequest == nil {
                if !expectedError {
                    XCTFail()
                }
                expectation.fulfill()
                return
            }
            
            self.performRequest(route: ServerEndpoints.downloadAppMetaData, headers: headers, urlParameters: "?" + downloadAppMetaDataRequest!.urlParameters()!, body:nil) { response, dict in
                Log.info("Status code: \(response!.statusCode)")
                
                if expectedError {
                    XCTAssert(response!.statusCode != .OK, "Did not work on failing downloadAppMetaDataRequest request")
                }
                else {
                    XCTAssert(response!.statusCode == .OK, "Did not work on downloadAppMetaDataRequest request")
                    
                    if let dict = dict,
                        let downloadAppMetaDataResponse = DownloadAppMetaDataResponse(json: dict) {
                        result = downloadAppMetaDataResponse
                        if expectUpdatedMasterUpdate {
                            XCTAssert(downloadAppMetaDataResponse.masterVersionUpdate != nil)
                        }
                        else {
                            XCTAssert(downloadAppMetaDataResponse.masterVersionUpdate == nil)
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
    
    func testDownloadAppMetaDataForBadUUIDFails() {
        let masterVersion: MasterVersionInt = 0
        let deviceUUID = PerfectLib.UUID().string
        let appMetaData = AppMetaData(version: 0, contents: "Test1")
        
        uploadTextFile(deviceUUID:deviceUUID, masterVersion:masterVersion, appMetaData:appMetaData)
        sendDoneUploads(expectedNumberOfUploads: 1, deviceUUID:deviceUUID, masterVersion: masterVersion)
    
        let badFileUUID = PerfectLib.UUID().string
        downloadAppMetaDataVersion(deviceUUID:deviceUUID, fileUUID: badFileUUID, masterVersionExpectedWithDownload:1, appMetaDataVersion: 0, expectedError: true)
    }
    
    func testDownloadAppMetaDataForReallyBadUUIDFails() {
        let masterVersion: MasterVersionInt = 0
        let deviceUUID = PerfectLib.UUID().string
        let appMetaData = AppMetaData(version: 0, contents: "Test1")

        uploadTextFile(deviceUUID:deviceUUID, masterVersion:masterVersion, appMetaData:appMetaData)
        sendDoneUploads(expectedNumberOfUploads: 1, deviceUUID:deviceUUID, masterVersion: masterVersion)
    
        let badFileUUID = "Blig"
        downloadAppMetaDataVersion(deviceUUID:deviceUUID, fileUUID: badFileUUID, masterVersionExpectedWithDownload:1, appMetaDataVersion: 0, expectedError: true)
    }
    
    func testDownloadAppMetaDataVersionNotOnServerFails() {
        let masterVersion: MasterVersionInt = 0
        let deviceUUID = PerfectLib.UUID().string
        let appMetaData = AppMetaData(version: 0, contents: "Test1")

        let (uploadRequest1, _) = uploadTextFile(deviceUUID:deviceUUID, masterVersion:masterVersion, appMetaData:appMetaData)
        sendDoneUploads(expectedNumberOfUploads: 1, deviceUUID:deviceUUID, masterVersion: masterVersion)

        downloadAppMetaDataVersion(deviceUUID:deviceUUID, fileUUID: uploadRequest1.fileUUID, masterVersionExpectedWithDownload:1, appMetaDataVersion: 1, expectedError: true)
    }

    func testDownloadNilAppMetaDataVersionAs0Fails() {
        var masterVersion: MasterVersionInt = 0
        let deviceUUID = PerfectLib.UUID().string
        
        let (uploadRequest1, _) = uploadTextFile(deviceUUID:deviceUUID, masterVersion:masterVersion)
        sendDoneUploads(expectedNumberOfUploads: 1, deviceUUID:deviceUUID, masterVersion: masterVersion)
        masterVersion += 1
        
        downloadAppMetaDataVersion(deviceUUID:deviceUUID, fileUUID: uploadRequest1.fileUUID, masterVersionExpectedWithDownload:masterVersion, appMetaDataVersion: 0, expectedError: true)
    }
    
    func testDownloadAppMetaDataForFileThatIsNotOwnedFails() {
        var masterVersion: MasterVersionInt = 0
        let deviceUUID = PerfectLib.UUID().string
        let appMetaData = AppMetaData(version: 0, contents: "Test1")

        let (uploadRequest1, _) = uploadTextFile(deviceUUID:deviceUUID, masterVersion:masterVersion, appMetaData:appMetaData)
        sendDoneUploads(expectedNumberOfUploads: 1, deviceUUID:deviceUUID, masterVersion: masterVersion)
        masterVersion += 1
        
        let deviceUUID2 = PerfectLib.UUID().string

        let nonOwningAccount:TestAccount = .secondaryOwningAccount
        guard let _ = addNewUser(testAccount: nonOwningAccount, deviceUUID:deviceUUID2) else {
            XCTFail()
            return
        }
        
        // Using masterVersion 0 here because that's what the nonOwningAccount will have at this point.
        downloadAppMetaDataVersion(testAccount: nonOwningAccount, deviceUUID:deviceUUID2, fileUUID: uploadRequest1.fileUUID, masterVersionExpectedWithDownload:0, appMetaDataVersion: 0, expectedError: true)
    }
    
    func testDownloadValidAppMetaDataVersion0() {
        let masterVersion: MasterVersionInt = 0
        let deviceUUID = PerfectLib.UUID().string
        let appMetaData = AppMetaData(version: 0, contents: "Test1")

        let (uploadRequest1, _) = uploadTextFile(deviceUUID:deviceUUID, masterVersion:masterVersion, appMetaData:appMetaData)
        sendDoneUploads(expectedNumberOfUploads: 1, deviceUUID:deviceUUID, masterVersion: masterVersion)

        guard let downloadAppMetaDataResponse = downloadAppMetaDataVersion(deviceUUID:deviceUUID, fileUUID: uploadRequest1.fileUUID, masterVersionExpectedWithDownload:1, appMetaDataVersion: 0) else {
            XCTFail()
            return
        }
        
        XCTAssert(downloadAppMetaDataResponse.appMetaData == appMetaData.contents)
    }
    
    func testDownloadValidAppMetaDataVersion1() {
        var masterVersion: MasterVersionInt = 0
        let deviceUUID = PerfectLib.UUID().string
        var appMetaData = AppMetaData(version: 0, contents: "Test1")
        
        let (uploadRequest1, _) = uploadTextFile(deviceUUID:deviceUUID, masterVersion:masterVersion, appMetaData:appMetaData)
        sendDoneUploads(expectedNumberOfUploads: 1, deviceUUID:deviceUUID, masterVersion: masterVersion)
        masterVersion += 1
        
        guard let downloadAppMetaDataResponse1 = downloadAppMetaDataVersion(deviceUUID:deviceUUID, fileUUID: uploadRequest1.fileUUID, masterVersionExpectedWithDownload:masterVersion, appMetaDataVersion: appMetaData.version) else {
            XCTFail()
            return
        }
        
        XCTAssert(downloadAppMetaDataResponse1.appMetaData == appMetaData.contents)
        
        // Second upload and download
        appMetaData = AppMetaData(version: 1, contents: "Test2")
        uploadTextFile(deviceUUID:deviceUUID, fileUUID: uploadRequest1.fileUUID, addUser: false, fileVersion: 1, masterVersion:masterVersion, appMetaData:appMetaData)
        sendDoneUploads(expectedNumberOfUploads: 1, deviceUUID:deviceUUID, masterVersion: masterVersion)
        masterVersion += 1
        
        guard let downloadAppMetaDataResponse2 = downloadAppMetaDataVersion(deviceUUID:deviceUUID, fileUUID: uploadRequest1.fileUUID, masterVersionExpectedWithDownload:masterVersion, appMetaDataVersion: appMetaData.version) else {
            XCTFail()
            return
        }
        
        XCTAssert(downloadAppMetaDataResponse2.appMetaData == appMetaData.contents)
    }
    
    // Upload app meta data version 0, then upload app meta version nil, and then make sure when you download you still have app meta version 0. i.e., nil doesn't overwrite a non-nil version.
    func testUploadingNilAppMetaDataDoesNotOverwriteCurrent() {
        var masterVersion: MasterVersionInt = 0
        let deviceUUID = PerfectLib.UUID().string
        let appMetaData = AppMetaData(version: 0, contents: "Test1")
        
        let (uploadRequest1, _) = uploadTextFile(deviceUUID:deviceUUID, masterVersion:masterVersion, appMetaData:appMetaData)
        sendDoneUploads(expectedNumberOfUploads: 1, deviceUUID:deviceUUID, masterVersion: masterVersion)
        masterVersion += 1
        
        uploadTextFile(deviceUUID:deviceUUID, fileUUID: uploadRequest1.fileUUID, addUser: false, fileVersion: 1, masterVersion:masterVersion)
        sendDoneUploads(expectedNumberOfUploads: 1, deviceUUID:deviceUUID, masterVersion: masterVersion)
        masterVersion += 1
        
        guard let downloadAppMetaDataResponse1 = downloadAppMetaDataVersion(deviceUUID:deviceUUID, fileUUID: uploadRequest1.fileUUID, masterVersionExpectedWithDownload:masterVersion, appMetaDataVersion: appMetaData.version) else {
            XCTFail()
            return
        }
        
        XCTAssert(downloadAppMetaDataResponse1.appMetaData == appMetaData.contents)
    }
}

extension FileController_DownloadAppMetaDataTests {
    static var allTests : [(String, (FileController_DownloadAppMetaDataTests) -> () throws -> Void)] {
        return [
            ("testDownloadAppMetaDataForBadUUIDFails", testDownloadAppMetaDataForBadUUIDFails),
            ("testDownloadAppMetaDataForReallyBadUUIDFails", testDownloadAppMetaDataForReallyBadUUIDFails),
            ("testDownloadAppMetaDataVersionNotOnServerFails", testDownloadAppMetaDataVersionNotOnServerFails),
            ("testDownloadNilAppMetaDataVersionAs0Fails", testDownloadNilAppMetaDataVersionAs0Fails),
            ("testDownloadAppMetaDataForFileThatIsNotOwnedFails", testDownloadAppMetaDataForFileThatIsNotOwnedFails),
            ("testDownloadValidAppMetaDataVersion0", testDownloadValidAppMetaDataVersion0),
            ("testDownloadValidAppMetaDataVersion1", testDownloadValidAppMetaDataVersion1),
            ("testUploadingNilAppMetaDataDoesNotOverwriteCurrent", testUploadingNilAppMetaDataDoesNotOverwriteCurrent),
        ]
    }
    
    func testLinuxTestSuiteIncludesAllTests() {
        linuxTestSuiteIncludesAllTests(testType:FileController_DownloadAppMetaDataTests.self)
    }
}

