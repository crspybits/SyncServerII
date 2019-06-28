//
//  TestingStorageLiveTests.swift
//  ServerTests
//
//  Created by Christopher G Prince on 6/27/19.
//

import XCTest
@testable import Server
import LoggerAPI
import HeliumLogger

class TestingStorageLiveTests: ServerTestCase, LinuxTestable {
    override func setUp() {
        super.setUp()
        Constants.session.loadTestingCloudStorage = true
    }

    func testUploadFile() {
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
}

extension TestingStorageLiveTests {
    static var allTests : [(String, (TestingStorageLiveTests) -> () throws -> Void)] {
        return [
            ("testUploadFile", testUploadFile)
        ]
    }
    
    func testLinuxTestSuiteIncludesAllTests() {
        linuxTestSuiteIncludesAllTests(testType: TestingStorageLiveTests.self)
    }
}
