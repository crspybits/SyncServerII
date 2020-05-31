//
//  SpecificDatabaseTests_UploadRequestLog.swift
//  ServerTests
//
//  Created by Christopher G Prince on 5/30/20.
//

import XCTest
@testable import Server
import LoggerAPI
import HeliumLogger
import Credentials
import CredentialsGoogle
import Foundation
import SyncServerShared

class SpecificDatabaseTests_UploadRequestLog: ServerTestCase, LinuxTestable {
    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    func testAddUpload() throws {
        let request = UploadRequestLog()
        request.fileUUID = UUID().uuidString
        request.fileVersion = 0
        request.uploadContents = "Some stuff"
        request.deviceUUID = UUID().uuidString
        request.committed = false
        
        let result = UploadRequestLogRepository(db).add(request: request)
        
        switch result {
        case .error:
            XCTFail()
        case .success:
            break
        }
    }
}

extension SpecificDatabaseTests_UploadRequestLog {
    static var allTests : [(String, (SpecificDatabaseTests_UploadRequestLog) -> () throws -> Void)] {
        return [
            ("testAddUpload", testAddUpload)
        ]
    }
    
    func testLinuxTestSuiteIncludesAllTests() {
        linuxTestSuiteIncludesAllTests(testType: SpecificDatabaseTests_UploadRequestLog.self)
    }
}
