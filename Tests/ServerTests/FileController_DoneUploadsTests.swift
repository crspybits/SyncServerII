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
import PerfectLib
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
        let deviceUUID = PerfectLib.UUID().string
        self.addNewUser(deviceUUID:deviceUUID)
        self.sendDoneUploads(expectedNumberOfUploads: 0)
    }
    
    func testDoneUploadsWithSingleUpload() {
        let deviceUUID = PerfectLib.UUID().string
        _ = uploadTextFile(deviceUUID:deviceUUID)
        self.sendDoneUploads(expectedNumberOfUploads: 1, deviceUUID:deviceUUID)
    }
    
    func testDoneUploadsWithTwoUploads() {
        let deviceUUID = PerfectLib.UUID().string
        _ = uploadTextFile(deviceUUID:deviceUUID)
        Log.info(message: "Done uploadTextFile")
        
        guard let _ = uploadJPEGFile(deviceUUID:deviceUUID, addUser:false) else {
            XCTFail()
            return
        }
        
        Log.info(message: "Done uploadJPEGFile")
        self.sendDoneUploads(expectedNumberOfUploads: 2, deviceUUID:deviceUUID)
        Log.info(message: "Done sendDoneUploads")
    }
    
    func testDoneUploadsThatUpdatesFileVersion() {
        let deviceUUID = PerfectLib.UUID().string
        let fileUUID = PerfectLib.UUID().string
        
        _ = uploadTextFile(deviceUUID:deviceUUID, fileUUID:fileUUID)
        self.sendDoneUploads(expectedNumberOfUploads: 1, deviceUUID:deviceUUID)
        
        _ = uploadTextFile(deviceUUID:deviceUUID, fileUUID:fileUUID, addUser:false, fileVersion:1, masterVersion: 1)
        self.sendDoneUploads(expectedNumberOfUploads: 1, deviceUUID:deviceUUID, masterVersion: 1)
    }
    
    func testDoneUploadsTwiceDoesNothingSecondTime() {
        let deviceUUID = PerfectLib.UUID().string
        _ = uploadTextFile(deviceUUID:deviceUUID)
        self.sendDoneUploads(expectedNumberOfUploads: 1, deviceUUID:deviceUUID)
        
        self.sendDoneUploads(expectedNumberOfUploads: 0, masterVersion: 1)
    }
    
    // If you first upload a file (followed by a DoneUploads), then delete it, and then upload again the last upload fails.
    func testThatUploadAfterUploadDeletionFails() {
        let deviceUUID = PerfectLib.UUID().string
        let (uploadRequest, _) = uploadTextFile(deviceUUID:deviceUUID)
        self.sendDoneUploads(expectedNumberOfUploads: 1, deviceUUID:deviceUUID)
        
        var masterVersion:MasterVersionInt = uploadRequest.masterVersion + MasterVersionInt(1)
        
        let uploadDeletionRequest = UploadDeletionRequest(json: [
            UploadDeletionRequest.fileUUIDKey: uploadRequest.fileUUID,
            UploadDeletionRequest.fileVersionKey: uploadRequest.fileVersion,
            UploadDeletionRequest.masterVersionKey: masterVersion
        ])!

        uploadDeletion(uploadDeletionRequest: uploadDeletionRequest, deviceUUID: deviceUUID, addUser: false)

        self.sendDoneUploads(expectedNumberOfUploads: 1, deviceUUID:deviceUUID, masterVersion: masterVersion)
        masterVersion += 1
        
        // Try upload again. This should fail.
        _ = uploadTextFile(deviceUUID:deviceUUID, fileUUID: uploadRequest.fileUUID, addUser: false, fileVersion: 1, masterVersion: masterVersion, errorExpected: true)
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
            ("testThatUploadAfterUploadDeletionFails", testThatUploadAfterUploadDeletionFails)
        ]
    }
    
    func testLinuxTestSuiteIncludesAllTests() {
        linuxTestSuiteIncludesAllTests(testType:FileController_DoneUploadsTests.self)
    }
}
