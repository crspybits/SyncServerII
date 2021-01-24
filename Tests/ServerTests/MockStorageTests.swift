//
//  MockStorageTests.swift
//  ServerTests
//
//  Created by Christopher G Prince on 6/27/19.
//

import XCTest
@testable import Server

class MockStorageTests: XCTestCase, LinuxTestable {
    func testUploadFile() {
        let storage = MockStorage()
        
        let exp = expectation(description: "upload")
        
        storage.uploadFile(cloudFileName: "foo", data: Data(), options: nil) { result in
            switch result {
            case .success:
                break
            default:
                XCTFail()
                break
            }
            exp.fulfill()
        }
        
        waitExpectation(timeout: 20, handler: nil)
    }
    
    func testDownloadFile() {
        let storage = MockStorage()
        
        let exp = expectation(description: "download")
        
        storage.downloadFile(cloudFileName: "foo", options: nil) { result in
            switch result {
            case .success:
                break
            default:
                XCTFail()
                break
            }
            exp.fulfill()
        }
        
        waitExpectation(timeout: 20, handler: nil)
    }

    func testDeleteFile() {
        let storage = MockStorage()
        
        let exp = expectation(description: "delete")
        
        storage.deleteFile(cloudFileName: "foo", options: nil) { result in
            switch result {
            case .success:
                break
            default:
                XCTFail()
                break
            }
            exp.fulfill()
        }
        
        waitExpectation(timeout: 20, handler: nil)
    }
    
    func testLookupFile() {
        let storage = MockStorage()
        
        let exp = expectation(description: "lookup")
        
        storage.lookupFile(cloudFileName: "foo", options: nil) { result in
            switch result {
            case .success:
                break
            default:
                XCTFail()
                break
            }
            exp.fulfill()
        }
        
        waitExpectation(timeout: 20, handler: nil)
    }
}

extension MockStorageTests {
    static var allTests : [(String, (MockStorageTests) -> () throws -> Void)] {
        return [
            ("testUploadFile", testUploadFile),
            ("testDownloadFile", testDownloadFile),
            ("testDeleteFile", testDeleteFile),
            ("testLookupFile", testLookupFile)
        ]
    }
    
    func testLinuxTestSuiteIncludesAllTests() {
        linuxTestSuiteIncludesAllTests(testType: MockStorageTests.self)
    }
}
