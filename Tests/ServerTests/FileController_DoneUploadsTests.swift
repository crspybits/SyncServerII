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
        guard let addUserResult = self.addNewUser(deviceUUID:deviceUUID) else {
            XCTFail()
            return
        }
        
        self.sendDoneUploads(expectedNumberOfUploads: 0, sharingGroupId: addUserResult.sharingGroupId)
    }
    
    func testDoneUploadsWithSingleUpload() {
        let deviceUUID = Foundation.UUID().uuidString
        guard let uploadResult = uploadTextFile(deviceUUID:deviceUUID), let sharingGroupId = uploadResult.sharingGroupId else {
            XCTFail()
            return
        }
        
        self.sendDoneUploads(expectedNumberOfUploads: 1, deviceUUID:deviceUUID, sharingGroupId: sharingGroupId)
    }
    
    func testDoneUploadsWithTwoUploads() {
        let deviceUUID = Foundation.UUID().uuidString
        guard let uploadResult = uploadTextFile(deviceUUID:deviceUUID), let sharingGroupId = uploadResult.sharingGroupId else {
            XCTFail()
            return
        }
        Log.info("Done uploadTextFile")
        
        guard let _ = uploadJPEGFile(deviceUUID:deviceUUID, addUser:.no(sharingGroupId: sharingGroupId)) else {
            XCTFail()
            return
        }
        
        Log.info("Done uploadJPEGFile")
        self.sendDoneUploads(expectedNumberOfUploads: 2, deviceUUID:deviceUUID, sharingGroupId: sharingGroupId)
        Log.info("Done sendDoneUploads")
    }
    
    func testDoneUploadsThatUpdatesFileVersion() {
        let deviceUUID = Foundation.UUID().uuidString
        let fileUUID = Foundation.UUID().uuidString
        
        guard let uploadResult1 = uploadTextFile(deviceUUID:deviceUUID, fileUUID: fileUUID), let sharingGroupId = uploadResult1.sharingGroupId else {
            XCTFail()
            return
        }
        
        self.sendDoneUploads(expectedNumberOfUploads: 1, deviceUUID:deviceUUID, sharingGroupId: sharingGroupId)
        
        guard let _ = uploadTextFile(deviceUUID:deviceUUID, fileUUID:fileUUID, addUser:.no(sharingGroupId: sharingGroupId), fileVersion:1, masterVersion: 1) else {
            XCTFail()
            return
        }
        
        self.sendDoneUploads(expectedNumberOfUploads: 1, deviceUUID:deviceUUID, masterVersion: 1, sharingGroupId: sharingGroupId)
    }
    
    func testDoneUploadsTwiceDoesNothingSecondTime() {
        let deviceUUID = Foundation.UUID().uuidString
        guard let uploadResult1 = uploadTextFile(deviceUUID:deviceUUID), let sharingGroupId = uploadResult1.sharingGroupId else {
            XCTFail()
            return
        }
        
        self.sendDoneUploads(expectedNumberOfUploads: 1, deviceUUID:deviceUUID, sharingGroupId: sharingGroupId)
        
        self.sendDoneUploads(expectedNumberOfUploads: 0, masterVersion: 1, sharingGroupId: sharingGroupId)
    }
    
    // If you first upload a file (followed by a DoneUploads), then delete it, and then upload again the last upload fails.
    func testThatUploadAfterUploadDeletionFails() {
        let deviceUUID = Foundation.UUID().uuidString
        guard let uploadResult1 = uploadTextFile(deviceUUID:deviceUUID),
            let sharingGroupId = uploadResult1.sharingGroupId else {
            XCTFail()
            return
        }
        
        self.sendDoneUploads(expectedNumberOfUploads: 1, deviceUUID:deviceUUID, sharingGroupId: sharingGroupId)
        
        var masterVersion:MasterVersionInt = uploadResult1.request.masterVersion + MasterVersionInt(1)
        
        let uploadDeletionRequest = UploadDeletionRequest(json: [
            UploadDeletionRequest.fileUUIDKey: uploadResult1.request.fileUUID,
            UploadDeletionRequest.fileVersionKey: uploadResult1.request.fileVersion,
            UploadDeletionRequest.masterVersionKey: masterVersion,
            ServerEndpoint.sharingGroupIdKey: sharingGroupId
        ])!

        uploadDeletion(uploadDeletionRequest: uploadDeletionRequest, deviceUUID: deviceUUID, addUser: false)

        self.sendDoneUploads(expectedNumberOfUploads: 1, deviceUUID:deviceUUID, masterVersion: masterVersion, sharingGroupId: sharingGroupId)
        masterVersion += 1
        
        // Try upload again. This should fail.
        uploadTextFile(deviceUUID:deviceUUID, fileUUID: uploadResult1.request.fileUUID, addUser: .no(sharingGroupId: sharingGroupId), fileVersion: 1, masterVersion: masterVersion, errorExpected: true)
    }
    
    func testDoneUploadsWithFakeSharingGroupIdFails() {
        let deviceUUID = Foundation.UUID().uuidString
        guard let _ = uploadTextFile(deviceUUID:deviceUUID) else {
            XCTFail()
            return
        }
        
        let invalidSharingGroupId: SharingGroupId = 100
        self.sendDoneUploads(expectedNumberOfUploads: 1, deviceUUID:deviceUUID, sharingGroupId: invalidSharingGroupId, failureExpected: true)
    }

    func testDoneUploadsWithBadSharingGroupIdFails() {
        let deviceUUID = Foundation.UUID().uuidString
        guard let _ = uploadTextFile(deviceUUID:deviceUUID) else {
            XCTFail()
            return
        }
        
        guard let workingButBadSharingGroupId = addSharingGroup() else {
            XCTFail()
            return
        }
        
        self.sendDoneUploads(expectedNumberOfUploads: 1, deviceUUID:deviceUUID, sharingGroupId: workingButBadSharingGroupId, failureExpected: true)
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
            ("testDoneUploadsWithBadSharingGroupIdFails", testDoneUploadsWithBadSharingGroupIdFails),
            ("testDoneUploadsWithFakeSharingGroupIdFails", testDoneUploadsWithFakeSharingGroupIdFails)
        ]
    }
    
    func testLinuxTestSuiteIncludesAllTests() {
        linuxTestSuiteIncludesAllTests(testType:FileController_DoneUploadsTests.self)
    }
}
