//
//  FileController_FileGroupUUID.swift
//  ServerTests
//
//  Created by Christopher G Prince on 4/20/18.
//

import XCTest
@testable import Server
import LoggerAPI
import Foundation
import PerfectLib
import SyncServerShared

class FileController_FileGroupUUIDTests: ServerTestCase, LinuxTestable {

    override func setUp() {
        super.setUp()
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }
    
    override func tearDown() {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
        super.tearDown()
    }

    func testUploadWithFileGroupUUIDWorks() {
        let deviceUUID = PerfectLib.UUID().string
        let fileGroupUUID = PerfectLib.UUID().string
        
        let (uploadRequest, _) = uploadTextFile(deviceUUID:deviceUUID, fileGroupUUID: fileGroupUUID)
        
        // Have to do a DoneUploads to transfer the files into the FileIndex
        self.sendDoneUploads(expectedNumberOfUploads: 1, deviceUUID:deviceUUID)
        
        guard let fileIndex = getFileIndex(deviceUUID:deviceUUID), fileIndex.count == 1 else {
            XCTFail()
            return
        }
        
        XCTAssert(uploadRequest.fileGroupUUID != nil)
        let fileInfo = fileIndex[0]
        XCTAssert(uploadRequest.fileGroupUUID == fileInfo.fileGroupUUID)
    }
    
    // Make sure when uploading version 1 of a file, given with nil fileGroupUUID, the fileGroupUUID doesn't reset to nil-- when you gave a fileGroupUUID when uploading v0
    func testUploadVersion1WithNilFileGroupUUIDWorks() {
        let deviceUUID = PerfectLib.UUID().string
        let fileGroupUUID = PerfectLib.UUID().string
        
        // Upload v0, with fileGroupUUID
        let (uploadRequest, _) = uploadTextFile(deviceUUID: deviceUUID, fileGroupUUID: fileGroupUUID)
        sendDoneUploads(expectedNumberOfUploads: 1, deviceUUID:deviceUUID)

        // Upload v1 with nil fileGroupUUID
        uploadTextFile(deviceUUID:deviceUUID, fileUUID:uploadRequest.fileUUID, addUser:false, fileVersion:1, masterVersion: 1)
        sendDoneUploads(expectedNumberOfUploads: 1, deviceUUID:deviceUUID, masterVersion: 1)

        guard let fileIndex = getFileIndex(deviceUUID:deviceUUID), fileIndex.count == 1 else {
            XCTFail()
            return
        }
        
        // Make sure we have v0 fileGroupUUID
        let fileInfo = fileIndex[0]
        XCTAssert(fileGroupUUID == fileInfo.fileGroupUUID)
    }
    
    // Give fileGroupUUID with version 1 of file (but not with v0)-- make sure this fails.
    func testFileGroupUUIDOnlyWithVersion1Fails() {
        let deviceUUID = PerfectLib.UUID().string
        let fileGroupUUID = PerfectLib.UUID().string
        
        // Upload v0, *without* fileGroupUUID
        let (uploadRequest, _) = uploadTextFile(deviceUUID: deviceUUID)
        sendDoneUploads(expectedNumberOfUploads: 1, deviceUUID:deviceUUID)

        // Upload v1 *with* fileGroupUUID
        uploadTextFile(deviceUUID:deviceUUID, fileUUID:uploadRequest.fileUUID, addUser:false, fileVersion:1, masterVersion: 1, errorExpected: true, fileGroupUUID: fileGroupUUID)
    }
}

extension FileController_FileGroupUUIDTests {
    static var allTests : [(String, (FileController_FileGroupUUIDTests) -> () throws -> Void)] {
        return [
            ("testUploadWithFileGroupUUIDWorks", testUploadWithFileGroupUUIDWorks),
            ("testUploadVersion1WithNilFileGroupUUIDWorks", testUploadVersion1WithNilFileGroupUUIDWorks),
            ("testFileGroupUUIDOnlyWithVersion1Fails", testFileGroupUUIDOnlyWithVersion1Fails)
        ]
    }
    
    func testLinuxTestSuiteIncludesAllTests() {
        linuxTestSuiteIncludesAllTests(testType:FileController_MultiVersionFiles.self)
    }
}
