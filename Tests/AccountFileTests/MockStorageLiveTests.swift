//
//  MockStorageLiveTests.swift
//  ServerTests
//
//  Created by Christopher G Prince on 6/27/19.
//

import XCTest
@testable import Server
@testable import TestsCommon
import LoggerAPI
import HeliumLogger
import ServerShared

class MockStorageLiveTests: ServerTestCase, LinuxTestable {
    override func setUp() {
        super.setUp()
        Configuration.setupLoadTestingCloudStorage()
    }

    func testUploadFile() {
        let deviceUUID = Foundation.UUID().uuidString
        guard let result = uploadTextFile(uploadIndex: 1, uploadCount: 1, deviceUUID:deviceUUID),
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
    
    func testDeleteFile() {
        let deviceUUID = Foundation.UUID().uuidString
        
        // This file is going to be deleted.
        guard let uploadResult1 = uploadTextFile(uploadIndex: 1, uploadCount: 1, deviceUUID:deviceUUID),
            let sharingGroupUUID = uploadResult1.sharingGroupUUID else {
            XCTFail()
            return
        }
        
        self.sendDoneUploads(expectedNumberOfUploads: 1, deviceUUID:deviceUUID, sharingGroupUUID: sharingGroupUUID)
        
        let uploadDeletionRequest = UploadDeletionRequest()
        uploadDeletionRequest.fileUUID = uploadResult1.request.fileUUID
        uploadDeletionRequest.sharingGroupUUID = sharingGroupUUID
        
        uploadDeletion(uploadDeletionRequest: uploadDeletionRequest, deviceUUID: deviceUUID, addUser: false)

        self.sendDoneUploads(expectedNumberOfUploads: 1, deviceUUID:deviceUUID, sharingGroupUUID: sharingGroupUUID)
    }
    
    func testDownloadFile() {
        downloadTextFile(masterVersionExpectedWithDownload: 1)
    }
}

extension MockStorageLiveTests {
    static var allTests : [(String, (MockStorageLiveTests) -> () throws -> Void)] {
        return [
            ("testUploadFile", testUploadFile),
            ("testDeleteFile", testDeleteFile),
            ("testDownloadFile", testDownloadFile)
        ]
    }
    
    func testLinuxTestSuiteIncludesAllTests() {
        linuxTestSuiteIncludesAllTests(testType: MockStorageLiveTests.self)
    }
}
