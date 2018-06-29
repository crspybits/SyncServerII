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
    
    func testDownloadAppMetaDataForBadUUIDFails() {
        let masterVersion: MasterVersionInt = 0
        let deviceUUID = Foundation.UUID().uuidString
        let appMetaData = AppMetaData(version: 0, contents: "Test1")
        
        guard let uploadResult1 = uploadTextFile(deviceUUID:deviceUUID, masterVersion:masterVersion, appMetaData:appMetaData), let sharingGroupId = uploadResult1.sharingGroupId else {
            XCTFail()
            return
        }
        
        sendDoneUploads(expectedNumberOfUploads: 1, deviceUUID:deviceUUID, masterVersion: masterVersion, sharingGroupId: sharingGroupId)
    
        let badFileUUID = Foundation.UUID().uuidString
        downloadAppMetaDataVersion(deviceUUID:deviceUUID, fileUUID: badFileUUID, masterVersionExpectedWithDownload:1, appMetaDataVersion: 0, expectedError: true)
    }
    
    func testDownloadAppMetaDataForReallyBadUUIDFails() {
        let masterVersion: MasterVersionInt = 0
        let deviceUUID = Foundation.UUID().uuidString
        let appMetaData = AppMetaData(version: 0, contents: "Test1")

        guard let uploadResult1 = uploadTextFile(deviceUUID:deviceUUID, masterVersion:masterVersion, appMetaData:appMetaData), let sharingGroupId = uploadResult1.sharingGroupId else {
            XCTFail()
            return
        }
        
        sendDoneUploads(expectedNumberOfUploads: 1, deviceUUID:deviceUUID, masterVersion: masterVersion, sharingGroupId: sharingGroupId)
    
        let badFileUUID = "Blig"
        downloadAppMetaDataVersion(deviceUUID:deviceUUID, fileUUID: badFileUUID, masterVersionExpectedWithDownload:1, appMetaDataVersion: 0, expectedError: true)
    }
    
    func testDownloadAppMetaDataVersionNotOnServerFails() {
        let masterVersion: MasterVersionInt = 0
        let deviceUUID = Foundation.UUID().uuidString
        let appMetaData = AppMetaData(version: 0, contents: "Test1")

        guard let uploadResult1 = uploadTextFile(deviceUUID:deviceUUID, masterVersion:masterVersion, appMetaData:appMetaData), let sharingGroupId = uploadResult1.sharingGroupId else {
            XCTFail()
            return
        }

        sendDoneUploads(expectedNumberOfUploads: 1, deviceUUID:deviceUUID, masterVersion: masterVersion, sharingGroupId: sharingGroupId)

        let badAppMetaDataVersion = appMetaData.version + 1
        downloadAppMetaDataVersion(deviceUUID:deviceUUID, fileUUID: uploadResult1.request.fileUUID, masterVersionExpectedWithDownload:1, appMetaDataVersion: badAppMetaDataVersion, expectedError: true)
    }

    func testDownloadNilAppMetaDataVersionAs0Fails() {
        var masterVersion: MasterVersionInt = 0
        let deviceUUID = Foundation.UUID().uuidString
        
        guard let uploadResult1 = uploadTextFile(deviceUUID:deviceUUID, masterVersion:masterVersion), let sharingGroupId = uploadResult1.sharingGroupId else {
            XCTFail()
            return
        }

        sendDoneUploads(expectedNumberOfUploads: 1, deviceUUID:deviceUUID, masterVersion: masterVersion, sharingGroupId: sharingGroupId)
        masterVersion += 1
        
        downloadAppMetaDataVersion(deviceUUID:deviceUUID, fileUUID: uploadResult1.request.fileUUID, masterVersionExpectedWithDownload:masterVersion, appMetaDataVersion: 0, expectedError: true)
    }
    
    func testDownloadAppMetaDataForFileThatIsNotOwnedFails() {
        var masterVersion: MasterVersionInt = 0
        let deviceUUID = Foundation.UUID().uuidString
        let appMetaData = AppMetaData(version: 0, contents: "Test1")

        guard let uploadResult1 = uploadTextFile(deviceUUID:deviceUUID, masterVersion:masterVersion, appMetaData:appMetaData), let sharingGroupId = uploadResult1.sharingGroupId else {
            XCTFail()
            return
        }
        
        sendDoneUploads(expectedNumberOfUploads: 1, deviceUUID:deviceUUID, masterVersion: masterVersion, sharingGroupId: sharingGroupId)
        masterVersion += 1
        
        let deviceUUID2 = Foundation.UUID().uuidString

        let nonOwningAccount:TestAccount = .secondaryOwningAccount
        guard let _ = addNewUser(testAccount: nonOwningAccount, deviceUUID:deviceUUID2) else {
            XCTFail()
            return
        }
        
        // Using masterVersion 0 here because that's what the nonOwningAccount will have at this point.
        downloadAppMetaDataVersion(testAccount: nonOwningAccount, deviceUUID:deviceUUID2, fileUUID: uploadResult1.request.fileUUID, masterVersionExpectedWithDownload:0, appMetaDataVersion: 0, expectedError: true)
    }
    
    func testDownloadValidAppMetaDataVersion0() {
        let masterVersion: MasterVersionInt = 0
        let deviceUUID = Foundation.UUID().uuidString
        let appMetaData = AppMetaData(version: 0, contents: "Test1")

        guard let uploadResult1 = uploadTextFile(deviceUUID:deviceUUID, masterVersion:masterVersion, appMetaData:appMetaData), let sharingGroupId = uploadResult1.sharingGroupId else {
            XCTFail()
            return
        }
        
        sendDoneUploads(expectedNumberOfUploads: 1, deviceUUID:deviceUUID, masterVersion: masterVersion, sharingGroupId: sharingGroupId)

        guard let downloadAppMetaDataResponse = downloadAppMetaDataVersion(deviceUUID:deviceUUID, fileUUID: uploadResult1.request.fileUUID, masterVersionExpectedWithDownload:1, appMetaDataVersion: 0) else {
            XCTFail()
            return
        }
        
        XCTAssert(downloadAppMetaDataResponse.appMetaData == appMetaData.contents)
    }
    
    func testDownloadValidAppMetaDataVersion1() {
        var masterVersion: MasterVersionInt = 0
        let deviceUUID = Foundation.UUID().uuidString
        var appMetaData = AppMetaData(version: 0, contents: "Test1")
        
        guard let uploadResult1 = uploadTextFile(deviceUUID:deviceUUID, masterVersion:masterVersion, appMetaData:appMetaData), let sharingGroupId = uploadResult1.sharingGroupId else {
            XCTFail()
            return
        }
        
        sendDoneUploads(expectedNumberOfUploads: 1, deviceUUID:deviceUUID, masterVersion: masterVersion, sharingGroupId: sharingGroupId)
        masterVersion += 1
        
        guard let downloadAppMetaDataResponse1 = downloadAppMetaDataVersion(deviceUUID:deviceUUID, fileUUID: uploadResult1.request.fileUUID, masterVersionExpectedWithDownload:masterVersion, appMetaDataVersion: appMetaData.version) else {
            XCTFail()
            return
        }
        
        XCTAssert(downloadAppMetaDataResponse1.appMetaData == appMetaData.contents)
        
        // Second upload and download
        appMetaData = AppMetaData(version: 1, contents: "Test2")
        uploadTextFile(deviceUUID:deviceUUID, fileUUID: uploadResult1.request.fileUUID, addUser: .no(sharingGroupId: sharingGroupId), fileVersion: 1, masterVersion:masterVersion, appMetaData:appMetaData)
        sendDoneUploads(expectedNumberOfUploads: 1, deviceUUID:deviceUUID, masterVersion: masterVersion, sharingGroupId: sharingGroupId)
        masterVersion += 1
        
        guard let downloadAppMetaDataResponse2 = downloadAppMetaDataVersion(deviceUUID:deviceUUID, fileUUID: uploadResult1.request.fileUUID, masterVersionExpectedWithDownload:masterVersion, appMetaDataVersion: appMetaData.version) else {
            XCTFail()
            return
        }
        
        XCTAssert(downloadAppMetaDataResponse2.appMetaData == appMetaData.contents)
    }
    
    // Upload app meta data version 0, then upload app meta version nil, and then make sure when you download you still have app meta version 0. i.e., nil doesn't overwrite a non-nil version.
    func testUploadingNilAppMetaDataDoesNotOverwriteCurrent() {
        var masterVersion: MasterVersionInt = 0
        let deviceUUID = Foundation.UUID().uuidString
        let appMetaData = AppMetaData(version: 0, contents: "Test1")
        
        guard let uploadResult1 = uploadTextFile(deviceUUID:deviceUUID, masterVersion:masterVersion, appMetaData:appMetaData), let sharingGroupId = uploadResult1.sharingGroupId else {
            XCTFail()
            return
        }
        
        sendDoneUploads(expectedNumberOfUploads: 1, deviceUUID:deviceUUID, masterVersion: masterVersion, sharingGroupId: sharingGroupId)
        masterVersion += 1
        
        guard let _ = uploadTextFile(deviceUUID:deviceUUID, fileUUID: uploadResult1.request.fileUUID, addUser: .no(sharingGroupId: sharingGroupId), fileVersion: 1, masterVersion:masterVersion) else {
            XCTFail()
            return
        }
        
        sendDoneUploads(expectedNumberOfUploads: 1, deviceUUID:deviceUUID, masterVersion: masterVersion, sharingGroupId: sharingGroupId)
        masterVersion += 1
        
        guard let downloadAppMetaDataResponse1 = downloadAppMetaDataVersion(deviceUUID:deviceUUID, fileUUID: uploadResult1.request.fileUUID, masterVersionExpectedWithDownload:masterVersion, appMetaDataVersion: appMetaData.version) else {
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

