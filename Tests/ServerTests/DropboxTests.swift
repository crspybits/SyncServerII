//
//  DropboxTests.swift
//  Server
//
//  Created by Christopher Prince on 12/10/17.
//
//

import XCTest
@testable import Server
import Foundation
import LoggerAPI
import HeliumLogger
import PerfectLib
import SyncServerShared

class DropboxTests: ServerTestCase, LinuxTestable {
    // In my Dropbox:
    let knownPresentFile = "DO-NOT-REMOVE.txt"
    let knownAbsentFile = "Markwa.Farkwa.Blarkwa"

    override func setUp() {
        super.setUp()
        HeliumLogger.use(.debug)
    }
    
    override func tearDown() {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
        super.tearDown()
    }

    func testCheckForFileFailsWithFileThatDoesNotExist() {
        let creds = DropboxCreds()
        creds.accessToken = TestAccount.dropbox1.token()
        creds.accountId = TestAccount.dropbox1.id()
        let exp = expectation(description: "\(#function)\(#line)")
        
        creds.checkForFile(fileName: "foobar") { result in
            switch result {
            case .success(let found):
                XCTAssert(!found)
            case .failure:
                XCTFail()
            }

            exp.fulfill()
        }

        waitForExpectations(timeout: 10, handler: nil)
    }
    
    func testCheckForFileWorksWithExistingFile() {
        let creds = DropboxCreds()
        creds.accessToken = TestAccount.dropbox1.token()
        creds.accountId = TestAccount.dropbox1.id()
        let exp = expectation(description: "\(#function)\(#line)")
        
        creds.checkForFile(fileName: knownPresentFile) { result in
            switch result {
            case .success(let found):
                XCTAssert(found)
            case .failure:
                XCTFail()
            }
            
            exp.fulfill()
        }
        
        waitForExpectations(timeout: 10, handler: nil)
    }
    
    func testUploadFileWorks() {
        let fileName = PerfectLib.UUID().string
        
        let creds = DropboxCreds()
        creds.accessToken = TestAccount.dropbox1.token()
        creds.accountId = TestAccount.dropbox1.id()
        let exp = expectation(description: "\(#function)\(#line)")
        
        let fileContents = "Hello World"
        let fileContentsData = fileContents.data(using: .ascii)!
        
        creds.uploadFile(withName: fileName, data: fileContentsData) { result in
            switch result {
            case .success(let size):
                XCTAssert(size == fileContents.count)
                Log.debug("size: \(size)")
            case .failure(let error):
                Log.error("uploadFile: \(error)")
                XCTFail()
            }
            
            exp.fulfill()
        }
        
        waitForExpectations(timeout: 10, handler: nil)
    }
    
    @discardableResult
    func uploadFile(creds: DropboxCreds, deviceUUID:String, fileContents: String, uploadRequest:UploadFileRequest, failureExpected: Bool = false) -> String {
        
        let fileContentsData = fileContents.data(using: .ascii)!
        let cloudFileName = uploadRequest.cloudFileName(deviceUUID:deviceUUID)
        
        let exp = expectation(description: "\(#function)\(#line)")

        creds.uploadFile(cloudFileName: cloudFileName, data: fileContentsData) { result in
            switch result {
            case .success(let size):
                XCTAssert(size == fileContents.count)
                Log.debug("size: \(size)")
                if failureExpected {
                    XCTFail()
                }
            case .failure(let error):
                Log.error("uploadFile: \(error)")
                if !failureExpected {
                    XCTFail()
                }
            }
            
            exp.fulfill()
        }
        
        waitForExpectations(timeout: 10, handler: nil)
        return cloudFileName
    }
    
    func testFullUploadWorks() {
        let deviceUUID = PerfectLib.UUID().string
        let fileUUID = PerfectLib.UUID().string
        
        let creds = DropboxCreds()
        creds.accessToken = TestAccount.dropbox1.token()
        creds.accountId = TestAccount.dropbox1.id()
        
        let fileContents = "Hello World"

        let uploadRequest = UploadFileRequest(json: [
            UploadFileRequest.fileUUIDKey : fileUUID,
            UploadFileRequest.mimeTypeKey: "text/plain",
            UploadFileRequest.fileVersionKey: 0,
            UploadFileRequest.masterVersionKey: 1
        ])!
        
        uploadFile(creds: creds, deviceUUID:deviceUUID, fileContents:fileContents, uploadRequest:uploadRequest)
        
        // The second time we try it, it should fail-- same file.
        uploadFile(creds: creds, deviceUUID:deviceUUID, fileContents:fileContents, uploadRequest:uploadRequest, failureExpected: true)
    }
    
    func downloadFile(creds: DropboxCreds, cloudFileName: String, expectedContents:String? = nil, expectedFailure: Bool = false) {
        let exp = expectation(description: "\(#function)\(#line)")

        creds.downloadFile(cloudFileName: cloudFileName) { result in
            switch result {
            case .success(let data):
                if let expectedContents = expectedContents {
                    guard let str = String(data: data, encoding: String.Encoding.ascii) else {
                        XCTFail()
                        Log.error("Failed on string decoding")
                        return
                    }
                    XCTAssert(str == expectedContents)
                }
                if expectedFailure {
                    XCTFail()
                }
            case .failure(let error):
                if !expectedFailure {
                    XCTFail()
                    Log.error("Failed download: \(error)")
                }
            }
            
            exp.fulfill()
        }
        
        waitForExpectations(timeout: 10, handler: nil)
    }
    
    func testDownloadOfNonExistingFileFails() {
        let creds = DropboxCreds()
        creds.accessToken = TestAccount.dropbox1.token()
        creds.accountId = TestAccount.dropbox1.id()
        downloadFile(creds: creds, cloudFileName: knownAbsentFile, expectedFailure: true)
    }
    
    func testSimpleDownloadWorks() {
        let creds = DropboxCreds()
        creds.accessToken = TestAccount.dropbox1.token()
        creds.accountId = TestAccount.dropbox1.id()
        
        downloadFile(creds: creds, cloudFileName: knownPresentFile)
    }
    
    func testUploadAndDownloadWorks() {
        let deviceUUID = PerfectLib.UUID().string
        let fileUUID = PerfectLib.UUID().string
        
        let creds = DropboxCreds()
        creds.accessToken = TestAccount.dropbox1.token()
        creds.accountId = TestAccount.dropbox1.id()
        
        let fileContents = "Hello World"

        let uploadRequest = UploadFileRequest(json: [
            UploadFileRequest.fileUUIDKey : fileUUID,
            UploadFileRequest.mimeTypeKey: "text/plain",
            UploadFileRequest.fileVersionKey: 0,
            UploadFileRequest.masterVersionKey: 1
        ])!
        
        uploadFile(creds: creds, deviceUUID:deviceUUID, fileContents:fileContents, uploadRequest:uploadRequest)
        
        let cloudFileName = uploadRequest.cloudFileName(deviceUUID:deviceUUID)
        Log.debug("cloudFileName: \(cloudFileName)")
        downloadFile(creds: creds, cloudFileName: cloudFileName, expectedContents: fileContents)
    }
    
    func deleteFile(creds: DropboxCreds, cloudFileName: String, expectedFailure: Bool = false) {
        let exp = expectation(description: "\(#function)\(#line)")

        creds.deleteFile(cloudFileName: cloudFileName) { error in
            if error == nil {
                 if expectedFailure {
                    XCTFail()
                }
            }
            else {
                if !expectedFailure {
                    XCTFail()
                    Log.error("Failed download: \(error!)")
                }
            }
            
            exp.fulfill()
        }
        
        waitForExpectations(timeout: 10, handler: nil)
    }
    
    func testDeletionOfNonExistingFileFails() {
        let creds = DropboxCreds()
        creds.accessToken = TestAccount.dropbox1.token()
        creds.accountId = TestAccount.dropbox1.id()
        deleteFile(creds: creds, cloudFileName: knownAbsentFile, expectedFailure: true)
    }

    func testDeletionOfExistingFileWorks() {
        let deviceUUID = PerfectLib.UUID().string
        let fileUUID = PerfectLib.UUID().string
        
        let creds = DropboxCreds()
        creds.accessToken = TestAccount.dropbox1.token()
        creds.accountId = TestAccount.dropbox1.id()
        
        let fileContents = "Hello World"

        let uploadRequest = UploadFileRequest(json: [
            UploadFileRequest.fileUUIDKey : fileUUID,
            UploadFileRequest.mimeTypeKey: "text/plain",
            UploadFileRequest.fileVersionKey: 0,
            UploadFileRequest.masterVersionKey: 1
        ])!
        
        let fileName = uploadFile(creds: creds, deviceUUID:deviceUUID, fileContents:fileContents, uploadRequest:uploadRequest)
        
        deleteFile(creds: creds, cloudFileName: fileName)
    }
}

extension DropboxTests {
    static var allTests : [(String, (DropboxTests) -> () throws -> Void)] {
        return [
            ("testCheckForFileFailsWithFileThatDoesNotExist", testCheckForFileFailsWithFileThatDoesNotExist),
            ("testCheckForFileWorksWithExistingFile", testCheckForFileWorksWithExistingFile),
            ("testUploadFileWorks", testUploadFileWorks),
            ("testFullUploadWorks", testFullUploadWorks),
            ("testDownloadOfNonExistingFileFails", testDownloadOfNonExistingFileFails),
            ("testSimpleDownloadWorks", testSimpleDownloadWorks),
            ("testUploadAndDownloadWorks", testUploadAndDownloadWorks),
            ("testDeletionOfNonExistingFileFails", testDeletionOfNonExistingFileFails),
            ("testDeletionOfExistingFileWorks", testDeletionOfExistingFileWorks)
        ]
    }
    
    func testLinuxTestSuiteIncludesAllTests() {
        linuxTestSuiteIncludesAllTests(testType:DropboxTests.self)
    }
}

