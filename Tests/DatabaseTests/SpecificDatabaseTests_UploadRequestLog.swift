//
//  SpecificDatabaseTests_UploadRequestLog.swift
//  ServerTests
//
//  Created by Christopher G Prince on 5/30/20.
//

import XCTest
@testable import Server
@testable import TestsCommon
import LoggerAPI
import HeliumLogger
import Credentials
import CredentialsGoogle
import Foundation
import ServerShared

class SpecificDatabaseTests_UploadRequestLog: ServerTestCase, LinuxTestable {
    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.
        super.setUp()
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
        super.tearDown()
    }

    func testAddUpload() throws {
        let request = UploadRequestLog()
        request.userId = 0
        request.sharingGroupUUID = UUID().uuidString
        request.fileUUID = UUID().uuidString
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
    
    func testLookupFromUploadLogExisting() {
        let request = UploadRequestLog()
        request.userId = 0
        request.sharingGroupUUID = UUID().uuidString
        request.fileUUID = UUID().uuidString
        request.uploadContents = "Some stuff"
        request.deviceUUID = UUID().uuidString
        request.committed = false
        
        let result = UploadRequestLogRepository(db).add(request: request)
        
        guard case .success = result else {
            XCTFail()
            return
        }
        
        let key = UploadRequestLogRepository.LookupKey.primaryKeys(fileUUID: request.fileUUID, deviceUUID: request.deviceUUID)
        let result2 = UploadRequestLogRepository(db).lookup(key: key, modelInit: UploadRequestLog.init)
        switch result2 {
        case .found(let model):
            guard let obj = model as? UploadRequestLog else {
                XCTFail()
                return
            }
            
            XCTAssert(obj.userId == request.userId)
            XCTAssert(obj.sharingGroupUUID == request.sharingGroupUUID)
            XCTAssert(obj.fileUUID == request.fileUUID)
            XCTAssert(obj.uploadContents == request.uploadContents, "\(String(describing: obj.uploadContents)) != \(String(describing: request.uploadContents))")
            XCTAssert(obj.deviceUUID == request.deviceUUID)
            XCTAssert(obj.committed == request.committed)

        case .noObjectFound:
            XCTFail("No object found")
        case .error(let error):
            XCTFail("Error: \(error)")
        }
    }
    
    func testLookupFromUploadLogNonExisting() {
        let key = UploadRequestLogRepository.LookupKey.primaryKeys(fileUUID: UUID().uuidString, deviceUUID: UUID().uuidString)
        let result = UploadRequestLogRepository(db).lookup(key: key, modelInit: UploadRequestLog.init)
        switch result {
        case .found:
            XCTFail()
        case .noObjectFound:
            break
        case .error(let error):
            XCTFail("Error: \(error)")
        }
    }
    
    func testRemoveRow() {
        let request = UploadRequestLog()
        request.userId = 0
        request.sharingGroupUUID = UUID().uuidString
        request.fileUUID = UUID().uuidString
        request.uploadContents = "Some stuff"
        request.deviceUUID = UUID().uuidString
        request.committed = false
        
        let result = UploadRequestLogRepository(db).add(request: request)
        
        guard case .success = result else {
            XCTFail()
            return
        }
        
        let key = UploadRequestLogRepository.LookupKey.primaryKeys(fileUUID: request.fileUUID, deviceUUID: request.deviceUUID)
        let result2 = UploadRequestLogRepository(db).lookup(key: key, modelInit: UploadRequestLog.init)
        switch result2 {
        case .found(let model):
            guard let obj = model as? UploadRequestLog else {
                XCTFail()
                return
            }
            
            XCTAssert(obj.userId == request.userId)
            XCTAssert(obj.sharingGroupUUID == request.sharingGroupUUID)
            XCTAssert(obj.fileUUID == request.fileUUID)
            XCTAssert(obj.uploadContents == request.uploadContents, "\(String(describing: obj.uploadContents)) != \(String(describing: request.uploadContents))")
            XCTAssert(obj.deviceUUID == request.deviceUUID)
            XCTAssert(obj.committed == request.committed)

        case .noObjectFound:
            XCTFail("No object found")
        case .error(let error):
            XCTFail("Error: \(error)")
        }
        
        let removalResult = UploadRequestLogRepository(db).remove(key: key)
        guard case .removed(numberRows:let number) = removalResult,
            number == 1 else{
            XCTFail()
            return
        }
    }
}

extension SpecificDatabaseTests_UploadRequestLog {
    static var allTests : [(String, (SpecificDatabaseTests_UploadRequestLog) -> () throws -> Void)] {
        return [
            ("testAddUpload", testAddUpload),
            ("testLookupFromUploadLogExisting", testLookupFromUploadLogExisting),
            ("testLookupFromUploadLogNonExisting", testLookupFromUploadLogNonExisting),
            ("testRemoveRow", testRemoveRow)
        ]
    }
    
    func testLinuxTestSuiteIncludesAllTests() {
        linuxTestSuiteIncludesAllTests(testType: SpecificDatabaseTests_UploadRequestLog.self)
    }
}
