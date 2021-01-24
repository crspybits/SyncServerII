//
//  FileController_DownloadAppMetaDataTests.swift
//  ServerTests
//
//  Created by Christopher G Prince on 3/24/18.
//

import XCTest
@testable import Server
@testable import TestsCommon
import LoggerAPI
import Foundation
import ServerShared
import HeliumLogger
import ChangeResolvers

class FileController_DownloadAppMetaDataTests: ServerTestCase {
    
    override func setUp() {
        super.setUp()
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }
    
    override func tearDown() {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
        super.tearDown()
    }

    func testDownloadAppMetaDataForBadUUIDFails() {
        let deviceUUID = Foundation.UUID().uuidString
        let appMetaData = "Test1"
        
        guard let uploadResult1 = uploadTextFile(deviceUUID:deviceUUID, fileLabel: UUID().uuidString, appMetaData:appMetaData),
            let sharingGroupUUID = uploadResult1.sharingGroupUUID else {
            XCTFail()
            return
        }

    
        let badFileUUID = Foundation.UUID().uuidString
        downloadAppMetaDataVersion(deviceUUID:deviceUUID, fileUUID: badFileUUID, sharingGroupUUID: sharingGroupUUID, expectedError: true)
    }
    
    func testDownloadAppMetaDataForReallyBadUUIDFails() {
        let deviceUUID = Foundation.UUID().uuidString
        let appMetaData = "Test1"

        guard let uploadResult1 = uploadTextFile(deviceUUID:deviceUUID, fileLabel: UUID().uuidString, appMetaData:appMetaData), let sharingGroupUUID = uploadResult1.sharingGroupUUID else {
            XCTFail()
            return
        }
    
        let badFileUUID = "Blig"
        downloadAppMetaDataVersion(deviceUUID:deviceUUID, fileUUID: badFileUUID, sharingGroupUUID: sharingGroupUUID, expectedError: true)
    }
    
    func testDownloadAppMetaDataForFileThatIsNotOwnedFails() {
        let deviceUUID = Foundation.UUID().uuidString
        let appMetaData = "Test1"

        Log.debug("About to uploadTextFile")
        
        guard let uploadResult1 = uploadTextFile(deviceUUID:deviceUUID, fileLabel: UUID().uuidString, appMetaData:appMetaData) else {
            XCTFail()
            return
        }
        
        let deviceUUID2 = Foundation.UUID().uuidString
        
        Log.debug("About to addNewUser")

        let nonOwningAccount:TestAccount = .dropbox1
        let sharingGroupUUID2 = UUID().uuidString
        guard let _ = addNewUser(testAccount: nonOwningAccount, sharingGroupUUID: sharingGroupUUID2, deviceUUID:deviceUUID2) else {
            XCTFail()
            return
        }
        
        Log.debug("About to downloadAppMetaDataVersion")

        downloadAppMetaDataVersion(testAccount: nonOwningAccount, deviceUUID:deviceUUID2, fileUUID: uploadResult1.request.fileUUID, sharingGroupUUID: sharingGroupUUID2, expectedError: true)
    }
    
    func testDownloadValidAppMetaDataVersion0() {
        let deviceUUID = Foundation.UUID().uuidString
        let appMetaData = "Test1"

        guard let uploadResult1 = uploadTextFile(deviceUUID:deviceUUID, fileLabel: UUID().uuidString, appMetaData:appMetaData),
            let sharingGroupUUID = uploadResult1.sharingGroupUUID else {
            XCTFail()
            return
        }

        guard let downloadAppMetaDataResponse = downloadAppMetaDataVersion(deviceUUID:deviceUUID, fileUUID: uploadResult1.request.fileUUID, sharingGroupUUID: sharingGroupUUID) else {
            XCTFail()
            return
        }
        
        XCTAssert(downloadAppMetaDataResponse.appMetaData == appMetaData)
    }
    
    func testDownloadValidAppMetaDataVersion1() {
        let deviceUUID = Foundation.UUID().uuidString
        var appMetaData = "Test1"
        
        guard let uploadResult1 = uploadTextFile(deviceUUID:deviceUUID, fileLabel: UUID().uuidString, appMetaData:appMetaData),
            let sharingGroupUUID = uploadResult1.sharingGroupUUID else {
            XCTFail()
            return
        }
        
        guard let downloadAppMetaDataResponse1 = downloadAppMetaDataVersion(deviceUUID:deviceUUID, fileUUID: uploadResult1.request.fileUUID, sharingGroupUUID: sharingGroupUUID) else {
            XCTFail()
            return
        }
        
        XCTAssert(downloadAppMetaDataResponse1.appMetaData == appMetaData)
        
        // Expect an error here because you can only upload app meta data with version 0 of the file.
        appMetaData = "Test2"
        uploadTextFile(deviceUUID:deviceUUID, fileUUID: uploadResult1.request.fileUUID, addUser: .no(sharingGroupUUID: sharingGroupUUID), fileLabel: nil, appMetaData:appMetaData, errorExpected: true)
    }
    
    // Upload app meta data version 0, then upload app meta version nil, and then make sure when you download you still have app meta version 0. i.e., nil doesn't overwrite a non-nil version.
    func testUploadingNilAppMetaDataDoesNotOverwriteCurrent() {
        let deviceUUID = Foundation.UUID().uuidString
        let appMetaData = "Test1"
        let file: TestFile = .commentFile
        
        guard let uploadResult1 = uploadTextFile(deviceUUID:deviceUUID, fileLabel: UUID().uuidString, appMetaData:appMetaData, stringFile: file, changeResolverName: CommentFile.changeResolverName),
            let sharingGroupUUID = uploadResult1.sharingGroupUUID else {
            XCTFail()
            return
        }
        
        let comment1 = ExampleComment(messageString: "Example", id: Foundation.UUID().uuidString)

        guard let _ = uploadTextFile(mimeType: nil, deviceUUID:deviceUUID, fileUUID: uploadResult1.request.fileUUID, addUser: .no(sharingGroupUUID: sharingGroupUUID), fileLabel: nil, dataToUpload: comment1.updateContents) else {
            XCTFail()
            return
        }
        
        guard let downloadAppMetaDataResponse1 = downloadAppMetaDataVersion(deviceUUID:deviceUUID, fileUUID: uploadResult1.request.fileUUID, sharingGroupUUID: sharingGroupUUID) else {
            XCTFail()
            return
        }
        
        XCTAssert(downloadAppMetaDataResponse1.appMetaData == appMetaData)
    }
    
    func testDownloadAppMetaDataWithFakeSharingGroupUUIDFails() {
        let deviceUUID = Foundation.UUID().uuidString
        let appMetaData = "Test1"

        guard let uploadResult1 = uploadTextFile(deviceUUID:deviceUUID, fileLabel: UUID().uuidString, appMetaData:appMetaData) else {
            XCTFail()
            return
        }

        let invalidSharingGroupUUID = UUID().uuidString
        downloadAppMetaDataVersion(deviceUUID:deviceUUID, fileUUID: uploadResult1.request.fileUUID, sharingGroupUUID: invalidSharingGroupUUID, expectedError: true)
    }
    
    func testDownloadAppMetaDataWithBadSharingGroupUUIDFails() {
        let deviceUUID = Foundation.UUID().uuidString
        let appMetaData = "Test1"

        guard let uploadResult1 = uploadTextFile(deviceUUID:deviceUUID, fileLabel: UUID().uuidString, appMetaData:appMetaData) else {
            XCTFail()
            return
        }

        let workingButBadSharingGroupUUID = UUID().uuidString
        guard addSharingGroup(sharingGroupUUID: workingButBadSharingGroupUUID) else {
            XCTFail()
            return
        }
        
        downloadAppMetaDataVersion(deviceUUID:deviceUUID, fileUUID: uploadResult1.request.fileUUID, sharingGroupUUID: workingButBadSharingGroupUUID, expectedError: true)
    }
}


