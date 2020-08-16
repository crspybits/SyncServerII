//
//  MockStorageTests.swift
//  ServerTests
//
//  Created by Christopher G Prince on 6/27/19.
//

import XCTest
@testable import Server
@testable import TestsCommon
import HeliumLogger

class MockStorageTests: XCTestCase {
    var storage:MockStorage!
    var data: Data!
    
    override func setUp() {
        super.setUp()
        data = "Hello, world!".data(using: .utf8)!
        storage = MockStorage()
        HeliumLogger.use(.verbose)
        MockStorage.reset()
    }
    
    func runUpload(cloudFileName: String, data: Data) -> Bool {
        let exp = expectation(description: "upload")
        var result: Bool = false
        
        storage.uploadFile(cloudFileName: cloudFileName, data: data, options: nil) { response in
            switch response {
            case .success:
                result = true
            default:
                result = false
            }
            exp.fulfill()
        }
        
        waitExpectation(timeout: 20, handler: nil)
        
        return result
    }
    
    func runDownload(cloudFileName: String) -> Data? {
        var result: Data?
        
        let exp = expectation(description: "download")
        
        storage.downloadFile(cloudFileName: cloudFileName, options: nil) { response in
            switch response {
            case .success(data: let data, checkSum: _):
                result = data
            default:
                break
            }
            
            exp.fulfill()
        }
        
        waitExpectation(timeout: 20, handler: nil)
        
        return result
    }

    func runDelete(cloudFileName: String) -> Bool {
        var result: Bool = false
        
        let exp = expectation(description: "download")
        
        storage.deleteFile(cloudFileName: cloudFileName, options: nil) { response in
            switch response {
            case .success:
                result = true
            default:
                break
            }
            
            exp.fulfill()
        }
        
        waitExpectation(timeout: 20, handler: nil)
        
        return result
    }
    
    func runLookup(cloudFileName: String) -> Bool {
        var result: Bool = false
        
        let exp = expectation(description: "lookup")
        
        storage.lookupFile(cloudFileName: cloudFileName, options: nil) { response in
            switch response {
            case .success(let found):
                result = found
                
            default:
                XCTFail()
                break
            }
            
            exp.fulfill()
        }
        
        waitExpectation(timeout: 20, handler: nil)
        
        return result
    }
    
    func testUploadFile() {
        guard runUpload(cloudFileName: "Test", data: data) else {
            XCTFail()
            return
        }
    }
    
    func testDownloadFileWorksWithExistingFile() {
        let cloudFileName = "Test"
        
        guard runUpload(cloudFileName: cloudFileName, data: data) else {
            XCTFail()
            return
        }
        
        guard let _ = runDownload(cloudFileName: cloudFileName) else {
            XCTFail()
            return
        }
    }
    
    func testDownloadFileFailsWithNonExistingFile() {
        let cloudFileName = "Test"
        
        let result = runDownload(cloudFileName: cloudFileName)
        XCTAssert(result == nil)
    }

    func testDeleteFileWorksWithExistingFile() {
        let cloudFileName = "Test"
        
        guard runUpload(cloudFileName: cloudFileName, data: data) else {
            XCTFail()
            return
        }
        
        guard runDelete(cloudFileName: cloudFileName) else {
            XCTFail()
            return
        }
    }
    
    func testDeleteFileFailsWithNonExistingFile() {
        let cloudFileName = "Test"
        
        guard !runDelete(cloudFileName: cloudFileName) else {
            XCTFail()
            return
        }
    }
    
    func testLookupFileWorksWithExistingFile() {
        let cloudFileName = "Test"
        
        guard runUpload(cloudFileName: cloudFileName, data: data) else {
            XCTFail()
            return
        }
        
        guard runLookup(cloudFileName: cloudFileName) else {
            XCTFail()
            return
        }
    }
    
    func testLookupFileFailsWithNonExistingFile() {
        let cloudFileName = "Test"
        
        guard !runLookup(cloudFileName: cloudFileName) else {
            XCTFail()
            return
        }
    }
}

