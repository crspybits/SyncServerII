//
//  FileController_FileGroupUUID.swift
//  ServerTests
//
//  Created by Christopher G Prince on 4/20/18.
//

import XCTest
@testable import Server
@testable import TestsCommon
import LoggerAPI
import Foundation
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
        let deviceUUID = Foundation.UUID().uuidString
        let fileGroupUUID = Foundation.UUID().uuidString
        
        guard let uploadResult1 = uploadTextFile(deviceUUID:deviceUUID, fileGroupUUID: fileGroupUUID), let sharingGroupUUID = uploadResult1.sharingGroupUUID else {
            XCTFail()
            return
        }
        
        // Have to do a DoneUploads to transfer the files into the FileIndex
        self.sendDoneUploads(expectedNumberOfUploads: 1, deviceUUID:deviceUUID, sharingGroupUUID: sharingGroupUUID)
        
        guard let (files, _) = getIndex(deviceUUID:deviceUUID, sharingGroupUUID: sharingGroupUUID),
            let fileIndex = files, fileIndex.count == 1 else {
            XCTFail()
            return
        }
        
        XCTAssert(uploadResult1.request.fileGroupUUID != nil)
        let fileInfo = fileIndex[0]
        XCTAssert(uploadResult1.request.fileGroupUUID == fileInfo.fileGroupUUID)
    }
    
    // Make sure when uploading version 1 of a file, given with nil fileGroupUUID, the fileGroupUUID doesn't reset to nil-- when you gave a fileGroupUUID when uploading v0
    func testUploadVersion1WithNilFileGroupUUIDWorks() {
        let deviceUUID = Foundation.UUID().uuidString
        let fileGroupUUID = Foundation.UUID().uuidString
        
        // Upload v0, with fileGroupUUID
        guard let uploadResult1 = uploadTextFile(deviceUUID:deviceUUID, fileGroupUUID: fileGroupUUID), let sharingGroupUUID = uploadResult1.sharingGroupUUID else {
            XCTFail()
            return
        }
        sendDoneUploads(expectedNumberOfUploads: 1, deviceUUID:deviceUUID, sharingGroupUUID: sharingGroupUUID)

        // Upload v1 with nil fileGroupUUID
        guard let _ = uploadTextFile(deviceUUID:deviceUUID, fileUUID:uploadResult1.request.fileUUID, addUser:.no(sharingGroupUUID: sharingGroupUUID), fileVersion:1, masterVersion: 1) else {
            XCTFail()
            return
        }
        
        sendDoneUploads(expectedNumberOfUploads: 1, deviceUUID:deviceUUID, masterVersion: 1, sharingGroupUUID: sharingGroupUUID)

        guard let (files, _) = getIndex(deviceUUID:deviceUUID, sharingGroupUUID: sharingGroupUUID), let fileIndex = files, fileIndex.count == 1 else {
            XCTFail()
            return
        }
        
        // Make sure we have v0 fileGroupUUID
        let fileInfo = fileIndex[0]
        XCTAssert(fileGroupUUID == fileInfo.fileGroupUUID)
    }
    
    // Give fileGroupUUID with version 1 of file (but not with v0)-- make sure this fails.
    func testFileGroupUUIDOnlyWithVersion1Fails() {
        let deviceUUID = Foundation.UUID().uuidString
        let fileGroupUUID = Foundation.UUID().uuidString
        
        // Upload v0, *without* fileGroupUUID
        guard let uploadResult1 = uploadTextFile(deviceUUID:deviceUUID), let sharingGroupUUID = uploadResult1.sharingGroupUUID else {
            XCTFail()
            return
        }
        
        sendDoneUploads(expectedNumberOfUploads: 1, deviceUUID:deviceUUID, sharingGroupUUID: sharingGroupUUID)

        // Upload v1 *with* fileGroupUUID
        uploadTextFile(deviceUUID:deviceUUID, fileUUID:uploadResult1.request.fileUUID, addUser:.no(sharingGroupUUID: sharingGroupUUID), fileVersion:1, masterVersion: 1, errorExpected: true, fileGroupUUID: fileGroupUUID)
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
