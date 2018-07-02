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
import SyncServerShared

class DropboxTests: ServerTestCase, LinuxTestable {
    // In my Dropbox:
    let knownPresentFile = "DO-NOT-REMOVE.txt"
    let knownPresentFile2 = "DO-NOT-REMOVE2.txt"

    let knownAbsentFile = "Markwa.Farkwa.Blarkwa"

    override func setUp() {
        super.setUp()
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
        let fileName = Foundation.UUID().uuidString
        
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
    
    func testFullUploadWorks() {
        let deviceUUID = Foundation.UUID().uuidString
        let fileUUID = Foundation.UUID().uuidString
        
        let creds = DropboxCreds()
        creds.accessToken = TestAccount.dropbox1.token()
        creds.accountId = TestAccount.dropbox1.id()
        
        let fileContents = "Hello World"

        let uploadRequest = UploadFileRequest(json: [
            UploadFileRequest.fileUUIDKey : fileUUID,
            UploadFileRequest.mimeTypeKey: "text/plain",
            UploadFileRequest.fileVersionKey: 0,
            UploadFileRequest.masterVersionKey: 1,
            ServerEndpoint.sharingGroupIdKey: 0
        ])!
        
        uploadFile(creds: creds, deviceUUID:deviceUUID, fileContents:fileContents, uploadRequest:uploadRequest)
        
        // The second time we try it, it should fail with CloudStorageError.alreadyUploaded -- same file.
        uploadFile(creds: creds, deviceUUID:deviceUUID, fileContents:fileContents, uploadRequest:uploadRequest, failureExpected: true, errorExpected: CloudStorageError.alreadyUploaded)
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
    
    func testSimpleDownloadWorks2() {
        let creds = DropboxCreds()
        creds.accessToken = TestAccount.dropbox1.token()
        creds.accountId = TestAccount.dropbox1.id()
        
        downloadFile(creds: creds, cloudFileName: knownPresentFile2)
    }
    
    func testUploadAndDownloadWorks() {
        let deviceUUID = Foundation.UUID().uuidString
        let fileUUID = Foundation.UUID().uuidString
        
        let creds = DropboxCreds()
        creds.accessToken = TestAccount.dropbox1.token()
        creds.accountId = TestAccount.dropbox1.id()
        
        let fileContents = "Hello World"

        let uploadRequest = UploadFileRequest(json: [
            UploadFileRequest.fileUUIDKey : fileUUID,
            UploadFileRequest.mimeTypeKey: "text/plain",
            UploadFileRequest.fileVersionKey: 0,
            UploadFileRequest.masterVersionKey: 1,
            ServerEndpoint.sharingGroupIdKey: 0
        ])!
        
        uploadFile(creds: creds, deviceUUID:deviceUUID, fileContents:fileContents, uploadRequest:uploadRequest)
        
        let cloudFileName = uploadRequest.cloudFileName(deviceUUID:deviceUUID, mimeType: uploadRequest.mimeType)
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
        let deviceUUID = Foundation.UUID().uuidString
        let fileUUID = Foundation.UUID().uuidString
        
        let creds = DropboxCreds()
        creds.accessToken = TestAccount.dropbox1.token()
        creds.accountId = TestAccount.dropbox1.id()
        
        let fileContents = "Hello World"

        let uploadRequest = UploadFileRequest(json: [
            UploadFileRequest.fileUUIDKey : fileUUID,
            UploadFileRequest.mimeTypeKey: "text/plain",
            UploadFileRequest.fileVersionKey: 0,
            UploadFileRequest.masterVersionKey: 1,
            ServerEndpoint.sharingGroupIdKey: 0
        ])!
        
        let fileName = uploadFile(creds: creds, deviceUUID:deviceUUID, fileContents:fileContents, uploadRequest:uploadRequest)
        
        deleteFile(creds: creds, cloudFileName: fileName)
    }
    
    func lookupFile(cloudFileName: String, expectError:Bool = false) -> Bool? {
        var foundResult: Bool?
        
        let creds = DropboxCreds()
        creds.accessToken = TestAccount.dropbox1.token()
        creds.accountId = TestAccount.dropbox1.id()
        
        let exp = expectation(description: "\(#function)\(#line)")
        
        creds.lookupFile(cloudFileName:cloudFileName) { result in
            switch result {
            case .success(let found):
                if expectError {
                    XCTFail()
                }
                else {
                   foundResult = found
                }
            case .failure:
                if !expectError {
                    XCTFail()
                }
            }
            
            exp.fulfill()
        }
        
        waitForExpectations(timeout: 10, handler: nil)
        return foundResult
    }
    
    func testLookupFileThatDoesNotExist() {
        let result = lookupFile(cloudFileName: knownPresentFile)
        XCTAssert(result == true)
    }
    
    func testLookupFileThatExists() {
        let result = lookupFile(cloudFileName: knownAbsentFile)
        XCTAssert(result == false)
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
            ("testSimpleDownloadWorks2", testSimpleDownloadWorks2),
            ("testUploadAndDownloadWorks", testUploadAndDownloadWorks),
            ("testDeletionOfNonExistingFileFails", testDeletionOfNonExistingFileFails),
            ("testDeletionOfExistingFileWorks", testDeletionOfExistingFileWorks),
            ("testLookupFileThatDoesNotExist", testLookupFileThatDoesNotExist),
            ("testLookupFileThatExists", testLookupFileThatExists)
        ]
    }
    
    func testLinuxTestSuiteIncludesAllTests() {
        linuxTestSuiteIncludesAllTests(testType:DropboxTests.self)
    }
}

