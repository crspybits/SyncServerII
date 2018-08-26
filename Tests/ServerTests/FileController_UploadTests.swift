//
//  FileController_UploadTests.swift
//  Server
//
//  Created by Christopher Prince on 3/22/17.
//
//

import XCTest
@testable import Server
import LoggerAPI
import Foundation
import SyncServerShared

class FileController_UploadTests: ServerTestCase, LinuxTestable {

    override func setUp() {
        super.setUp()
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }
    
    override func tearDown() {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
        super.tearDown()
    }
    
    func testUploadTextFile() {
        let deviceUUID = Foundation.UUID().uuidString
        guard let result = uploadTextFile(deviceUUID:deviceUUID),
            let sharingGroupUUID = result.sharingGroupUUID else {
            XCTFail()
            return
        }
        
        self.sendDoneUploads(expectedNumberOfUploads: 1, deviceUUID: deviceUUID, sharingGroupUUID: sharingGroupUUID)
        
        let fileIndexResult = FileIndexRepository(db).fileIndex(forSharingGroupUUID: sharingGroupUUID)
        switch fileIndexResult {
        case .fileIndex(let fileIndex):
            guard fileIndex.count == 1 else {
                XCTFail("fileIndex.count: \(fileIndex.count)")
                return
            }
            
            XCTAssert(fileIndex[0].fileUUID == result.request.fileUUID)
        case .error(_):
            XCTFail()
        }
    }
    
    func testUploadJPEGFile() {
        guard let _ = uploadJPEGFile() else {
            XCTFail()
            return
        }
    }
    
    func testUploadTextAndJPEGFile() {
        let deviceUUID = Foundation.UUID().uuidString
        guard let uploadResult = uploadTextFile(deviceUUID:deviceUUID),
            let sharingGroupUUID = uploadResult.sharingGroupUUID else {
            XCTFail()
            return
        }
        
        guard let _ = uploadJPEGFile(deviceUUID:deviceUUID, addUser:.no(sharingGroupUUID: sharingGroupUUID)) else {
            XCTFail()
            return
        }
    }
    
    func testUploadingSameFileTwiceWorks() {
        let deviceUUID = Foundation.UUID().uuidString
        guard let uploadResult = uploadTextFile(deviceUUID:deviceUUID),
            let sharingGroupUUID = uploadResult.sharingGroupUUID else {
            XCTFail()
            return
        }
        
        // Second upload.
        guard let _ = uploadTextFile(deviceUUID: deviceUUID, fileUUID: uploadResult.request.fileUUID, addUser: .no(sharingGroupUUID: sharingGroupUUID), fileVersion: uploadResult.request.fileVersion, masterVersion: uploadResult.request.masterVersion, appMetaData: uploadResult.request.appMetaData) else {
            XCTFail()
            return
        }
    }

    func testUploadTextFileWithStringWithSpacesAppMetaData() {
        guard let _ = uploadTextFile(appMetaData:AppMetaData(version: 0, contents: "A Simple String")) else {
            XCTFail()
            return
        }
    }
    
    func testUploadTextFileWithJSONAppMetaData() {
        guard let _ = uploadTextFile(appMetaData:AppMetaData(version: 0, contents: "{ \"foo\": \"bar\" }")) else {
            XCTFail()
            return
        }
    }
    
    func testUploadWithInvalidMimeTypeFails() {
        let testAccount:TestAccount = .primaryOwningAccount
        let deviceUUID = Foundation.UUID().uuidString
        let sharingGroupUUID = Foundation.UUID().uuidString

        guard let _ = addNewUser(sharingGroupUUID: sharingGroupUUID, deviceUUID:deviceUUID, cloudFolderName: ServerTestCase.cloudFolderName) else {
            XCTFail()
            return
        }
        
        let fileUUIDToSend = Foundation.UUID().uuidString
        
        let uploadString = ServerTestCase.uploadTextFileContents
        let data = ServerTestCase.uploadTextFileContents.data(using: .utf8)!
        
        let uploadRequest = UploadFileRequest(json: [
            UploadFileRequest.fileUUIDKey : fileUUIDToSend,
            UploadFileRequest.mimeTypeKey: "foobar",
            UploadFileRequest.fileVersionKey: 0,
            UploadFileRequest.masterVersionKey: 0,
            ServerEndpoint.sharingGroupUUIDKey: sharingGroupUUID
        ])!
        
        runUploadTest(testAccount:testAccount, data:data, uploadRequest:uploadRequest, expectedUploadSize:Int64(uploadString.count), deviceUUID:deviceUUID, errorExpected: true)
    }
    
    func testUploadWithInvalidSharingGroupIdFails() {
        guard let _ = uploadTextFile() else {
            XCTFail()
            return
        }
        
        let invalidSharingGroupUUID = UUID().uuidString
        uploadTextFile(addUser: .no(sharingGroupUUID: invalidSharingGroupUUID), errorExpected: true)
    }

    func testUploadWithBadSharingGroupIdFails() {
        guard let _ = uploadTextFile() else {
            XCTFail()
            return
        }
        
        let workingButBadSharingGroupUUID = UUID().uuidString
        guard addSharingGroup(sharingGroupUUID: workingButBadSharingGroupUUID) else {
            XCTFail()
            return
        }
        
        uploadTextFile(addUser: .no(sharingGroupUUID: workingButBadSharingGroupUUID), errorExpected: true)
    }
}

extension FileController_UploadTests {
    static var allTests : [(String, (FileController_UploadTests) -> () throws -> Void)] {
        return [
            ("testUploadTextFile", testUploadTextFile),
            ("testUploadJPEGFile", testUploadJPEGFile),
            ("testUploadTextAndJPEGFile", testUploadTextAndJPEGFile),
            ("testUploadingSameFileTwiceWorks", testUploadingSameFileTwiceWorks),
            ("testUploadTextFileWithStringWithSpacesAppMetaData", testUploadTextFileWithStringWithSpacesAppMetaData),
            ("testUploadTextFileWithJSONAppMetaData", testUploadTextFileWithJSONAppMetaData),
            ("testUploadWithInvalidMimeTypeFails", testUploadWithInvalidMimeTypeFails),
            ("testUploadWithInvalidSharingGroupIdFails", testUploadWithInvalidSharingGroupIdFails),
            ("testUploadWithBadSharingGroupIdFails", testUploadWithBadSharingGroupIdFails)
        ]
    }
    
    func testLinuxTestSuiteIncludesAllTests() {
        linuxTestSuiteIncludesAllTests(testType:FileController_UploadTests.self)
    }
}
