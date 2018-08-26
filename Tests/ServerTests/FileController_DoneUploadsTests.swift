//
//  FileController_DoneUploadsTests.swift
//  Server
//
//  Created by Christopher Prince on 3/23/17.
//
//

import XCTest
@testable import Server
import LoggerAPI
import Foundation
import SyncServerShared

class FileController_DoneUploadsTests: ServerTestCase, LinuxTestable {

    override func setUp() {
        super.setUp()
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }
    
    override func tearDown() {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
        super.tearDown()
    }
    
    func testDoneUploadsWithNoUploads() {
        let deviceUUID = Foundation.UUID().uuidString
        let sharingGroupUUID = Foundation.UUID().uuidString

        guard let _ = self.addNewUser(sharingGroupUUID: sharingGroupUUID, deviceUUID:deviceUUID) else {
            XCTFail()
            return
        }
        
        self.sendDoneUploads(expectedNumberOfUploads: 0, sharingGroupUUID: sharingGroupUUID)
    }
    
    func testDoneUploadsWithSingleUpload() {
        let deviceUUID = Foundation.UUID().uuidString
        guard let uploadResult = uploadTextFile(deviceUUID:deviceUUID), let sharingGroupUUID = uploadResult.sharingGroupUUID else {
            XCTFail()
            return
        }
        
        self.sendDoneUploads(expectedNumberOfUploads: 1, deviceUUID:deviceUUID, sharingGroupUUID: sharingGroupUUID)
    }
    
    func testDoneUploadsWithTwoUploads() {
        let deviceUUID = Foundation.UUID().uuidString
        guard let uploadResult = uploadTextFile(deviceUUID:deviceUUID),
            let sharingGroupUUID = uploadResult.sharingGroupUUID else {
            XCTFail()
            return
        }
        Log.info("Done uploadTextFile")
        
        guard let _ = uploadJPEGFile(deviceUUID:deviceUUID, addUser:.no(sharingGroupUUID: sharingGroupUUID)) else {
            XCTFail()
            return
        }
        
        Log.info("Done uploadJPEGFile")
        self.sendDoneUploads(expectedNumberOfUploads: 2, deviceUUID:deviceUUID, sharingGroupUUID: sharingGroupUUID)
        Log.info("Done sendDoneUploads")
    }
    
    func testDoneUploadsThatUpdatesFileVersion() {
        let deviceUUID = Foundation.UUID().uuidString
        let fileUUID = Foundation.UUID().uuidString
        
        guard let uploadResult1 = uploadTextFile(deviceUUID:deviceUUID, fileUUID: fileUUID), let sharingGroupUUID = uploadResult1.sharingGroupUUID else {
            XCTFail()
            return
        }
        
        self.sendDoneUploads(expectedNumberOfUploads: 1, deviceUUID:deviceUUID, sharingGroupUUID: sharingGroupUUID)
        
        guard let _ = uploadTextFile(deviceUUID:deviceUUID, fileUUID:fileUUID, addUser:.no(sharingGroupUUID: sharingGroupUUID), fileVersion:1, masterVersion: 1) else {
            XCTFail()
            return
        }
        
        self.sendDoneUploads(expectedNumberOfUploads: 1, deviceUUID:deviceUUID, masterVersion: 1, sharingGroupUUID: sharingGroupUUID)
    }
    
    func testDoneUploadsTwiceDoesNothingSecondTime() {
        let deviceUUID = Foundation.UUID().uuidString
        guard let uploadResult1 = uploadTextFile(deviceUUID:deviceUUID),
            let sharingGroupUUID = uploadResult1.sharingGroupUUID else {
            XCTFail()
            return
        }
        
        self.sendDoneUploads(expectedNumberOfUploads: 1, deviceUUID:deviceUUID, sharingGroupUUID: sharingGroupUUID)
        
        self.sendDoneUploads(expectedNumberOfUploads: 0, masterVersion: 1, sharingGroupUUID: sharingGroupUUID)
    }
    
    // If you first upload a file (followed by a DoneUploads), then delete it, and then upload again the last upload fails.
    func testThatUploadAfterUploadDeletionFails() {
        let deviceUUID = Foundation.UUID().uuidString
        guard let uploadResult1 = uploadTextFile(deviceUUID:deviceUUID),
            let sharingGroupUUID = uploadResult1.sharingGroupUUID else {
            XCTFail()
            return
        }
        
        self.sendDoneUploads(expectedNumberOfUploads: 1, deviceUUID:deviceUUID, sharingGroupUUID: sharingGroupUUID)
        
        var masterVersion:MasterVersionInt = uploadResult1.request.masterVersion + MasterVersionInt(1)
        
        let uploadDeletionRequest = UploadDeletionRequest(json: [
            UploadDeletionRequest.fileUUIDKey: uploadResult1.request.fileUUID,
            UploadDeletionRequest.fileVersionKey: uploadResult1.request.fileVersion,
            UploadDeletionRequest.masterVersionKey: masterVersion,
            ServerEndpoint.sharingGroupUUIDKey: sharingGroupUUID
        ])!

        uploadDeletion(uploadDeletionRequest: uploadDeletionRequest, deviceUUID: deviceUUID, addUser: false)

        self.sendDoneUploads(expectedNumberOfUploads: 1, deviceUUID:deviceUUID, masterVersion: masterVersion, sharingGroupUUID: sharingGroupUUID)
        masterVersion += 1
        
        // Try upload again. This should fail.
        uploadTextFile(deviceUUID:deviceUUID, fileUUID: uploadResult1.request.fileUUID, addUser: .no(sharingGroupUUID: sharingGroupUUID), fileVersion: 1, masterVersion: masterVersion, errorExpected: true)
    }
    
    func testDoneUploadsWithFakeSharingGroupUUIDFails() {
        let deviceUUID = Foundation.UUID().uuidString
        guard let _ = uploadTextFile(deviceUUID:deviceUUID) else {
            XCTFail()
            return
        }
        
        let invalidSharingGroupUUID = UUID().uuidString
        self.sendDoneUploads(expectedNumberOfUploads: 1, deviceUUID:deviceUUID, sharingGroupUUID: invalidSharingGroupUUID, failureExpected: true)
    }

    func testDoneUploadsWithBadSharingGroupUUIDFails() {
        let deviceUUID = Foundation.UUID().uuidString
        guard let _ = uploadTextFile(deviceUUID:deviceUUID) else {
            XCTFail()
            return
        }
        
        let workingButBadSharingGroupUUID = UUID().uuidString
        guard addSharingGroup(sharingGroupUUID: workingButBadSharingGroupUUID) else {
            XCTFail()
            return
        }
        
        self.sendDoneUploads(expectedNumberOfUploads: 1, deviceUUID:deviceUUID, sharingGroupUUID: workingButBadSharingGroupUUID, failureExpected: true)
    }
}

extension FileController_DoneUploadsTests {
    static var allTests : [(String, (FileController_DoneUploadsTests) -> () throws -> Void)] {
        return [
            ("testDoneUploadsWithNoUploads", testDoneUploadsWithNoUploads),
            ("testDoneUploadsWithSingleUpload", testDoneUploadsWithSingleUpload),
            ("testDoneUploadsWithTwoUploads", testDoneUploadsWithTwoUploads),
            ("testDoneUploadsThatUpdatesFileVersion", testDoneUploadsThatUpdatesFileVersion),
            ("testDoneUploadsTwiceDoesNothingSecondTime", testDoneUploadsTwiceDoesNothingSecondTime),
            ("testThatUploadAfterUploadDeletionFails", testThatUploadAfterUploadDeletionFails),
            ("testDoneUploadsWithBadSharingGroupUUIDFails", testDoneUploadsWithBadSharingGroupUUIDFails),
            ("testDoneUploadsWithFakeSharingGroupUUIDFails", testDoneUploadsWithFakeSharingGroupUUIDFails)
        ]
    }
    
    func testLinuxTestSuiteIncludesAllTests() {
        linuxTestSuiteIncludesAllTests(testType:FileController_DoneUploadsTests.self)
    }
}
