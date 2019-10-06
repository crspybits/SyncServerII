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

class FileDropboxTests: ServerTestCase, LinuxTestable {
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
        let creds = DropboxCreds()!
        creds.accessToken = TestAccount.dropbox1.token()
        creds.accountId = TestAccount.dropbox1.id()
        let exp = expectation(description: "\(#function)\(#line)")
        
        creds.checkForFile(fileName: "foobar") { result in
            switch result {
            case .success(let found):
                XCTAssert(!found)
            case .failure:
                XCTFail()
            case .accessTokenRevokedOrExpired:
                XCTFail()
            }

            exp.fulfill()
        }

        waitForExpectations(timeout: 10, handler: nil)
    }
    
    func testCheckForFileWorksWithExistingFile() {
        let creds = DropboxCreds()!
        creds.accessToken = TestAccount.dropbox1.token()
        creds.accountId = TestAccount.dropbox1.id()
        let exp = expectation(description: "\(#function)\(#line)")
        
        creds.checkForFile(fileName: knownPresentFile) { result in
            switch result {
            case .success(let found):
                XCTAssert(found)
            case .failure, .accessTokenRevokedOrExpired:
                XCTFail()
            }
            
            exp.fulfill()
        }
        
        waitForExpectations(timeout: 10, handler: nil)
    }
    
    func uploadFile(file: TestFile, mimeType: MimeType) {
        let fileName = Foundation.UUID().uuidString
        
        let creds = DropboxCreds()!
        creds.accessToken = TestAccount.dropbox1.token()
        creds.accountId = TestAccount.dropbox1.id()
        let exp = expectation(description: "\(#function)\(#line)")
        
        let fileContentsData: Data!

        switch file.contents {
        case .string(let fileContents):
            fileContentsData = fileContents.data(using: .ascii)!
        case .url(let url):
            fileContentsData = try? Data(contentsOf: url)
        }
        
        guard fileContentsData != nil else {
            XCTFail()
            return
        }
        
        creds.uploadFile(withName: fileName, data: fileContentsData) { result in
            switch result {
            case .success(let hash):
                XCTAssert(hash == file.dropboxCheckSum)
            case .failure(let error):
                Log.error("uploadFile: \(error)")
                XCTFail()
            case .accessTokenRevokedOrExpired:
                XCTFail()
            }
            
            exp.fulfill()
        }
        
        waitForExpectations(timeout: 10, handler: nil)
    }
    
    func testUploadFileWorks() {
        uploadFile(file: .test1, mimeType: .text)
    }
    
    func testUploadURLFileWorks() {
        uploadFile(file: .testUrlFile, mimeType: .url)
    }
    
    func testUploadWithRevokedToken() {
        let fileName = Foundation.UUID().uuidString
        
        let creds = DropboxCreds()!
        creds.accessToken = TestAccount.dropbox1Revoked.token()
        creds.accountId = TestAccount.dropbox1Revoked.id()
        let exp = expectation(description: "\(#function)\(#line)")
        
        let stringFile = TestFile.test1
        
        guard case .string(let stringContents) = stringFile.contents else {
            XCTFail()
            return
        }
        
        let fileContentsData = stringContents.data(using: .ascii)!
        
        creds.uploadFile(withName: fileName, data: fileContentsData) { result in
            switch result {
            case .success:
                XCTFail()
            case .failure(let error):
                Log.error("uploadFile: \(error)")
                XCTFail()
            case .accessTokenRevokedOrExpired:
                break
            }
            
            exp.fulfill()
        }
        
        waitForExpectations(timeout: 10, handler: nil)
    }
    
    func fullUpload(file: TestFile, mimeType: MimeType) {
        let deviceUUID = Foundation.UUID().uuidString
        let fileUUID = Foundation.UUID().uuidString
        
        let creds = DropboxCreds()!
        creds.accessToken = TestAccount.dropbox1.token()
        creds.accountId = TestAccount.dropbox1.id()
        
        let uploadRequest = UploadFileRequest()
        uploadRequest.fileUUID = fileUUID
        uploadRequest.mimeType = mimeType.rawValue
        uploadRequest.fileVersion = 0
        uploadRequest.masterVersion = 1
        uploadRequest.sharingGroupUUID = UUID().uuidString
        uploadRequest.checkSum = file.dropboxCheckSum
        
        uploadFile(accountType: AccountScheme.dropbox.accountName, creds: creds, deviceUUID:deviceUUID, testFile: file, uploadRequest:uploadRequest)
        
        // The second time we try it, it should fail with CloudStorageError.alreadyUploaded -- same file.
        uploadFile(accountType: AccountScheme.dropbox.accountName, creds: creds, deviceUUID:deviceUUID, testFile: file, uploadRequest:uploadRequest, failureExpected: true, errorExpected: CloudStorageError.alreadyUploaded)
    }
    
    func testFullUploadWorks() {
        fullUpload(file: .test1, mimeType: .text)
    }
    
    func testFullUploadURLWorks() {
        fullUpload(file: .testUrlFile, mimeType: .url)
    }
    
    func downloadFile(creds: DropboxCreds, cloudFileName: String, expectedStringFile:TestFile? = nil, expectedFailure: Bool = false, expectedFileNotFound: Bool = false, expectedRevokedToken: Bool = false) {
        let exp = expectation(description: "\(#function)\(#line)")

        creds.downloadFile(cloudFileName: cloudFileName) { result in
            switch result {
            case .success(let downloadResult):
                if let expectedStringFile = expectedStringFile {
                    guard case .string(let expectedContents) = expectedStringFile.contents else {
                        XCTFail()
                        return
                    }
                    
                    guard let str = String(data: downloadResult.data, encoding: String.Encoding.ascii) else {
                        XCTFail()
                        Log.error("Failed on string decoding")
                        return
                    }
                    
                    XCTAssert(downloadResult.checkSum == expectedStringFile.dropboxCheckSum)
                    XCTAssert(str == expectedContents)
                }
                
                if expectedFailure || expectedRevokedToken || expectedFileNotFound {
                    XCTFail()
                }
            case .failure(let error):
                if !expectedFailure || expectedRevokedToken || expectedFileNotFound {
                    XCTFail()
                    Log.error("Failed download: \(error)")
                }
            case .accessTokenRevokedOrExpired:
                if !expectedRevokedToken || expectedFileNotFound || expectedFailure {
                    XCTFail()
                }
            case .fileNotFound:
                if !expectedFileNotFound || expectedRevokedToken || expectedFailure{
                    XCTFail()
                }
            }
            
            exp.fulfill()
        }
        
        waitForExpectations(timeout: 10, handler: nil)
    }
    
    func testDownloadOfNonExistingFileFails() {
        let creds = DropboxCreds()!
        creds.accessToken = TestAccount.dropbox1.token()
        creds.accountId = TestAccount.dropbox1.id()
        downloadFile(creds: creds, cloudFileName: knownAbsentFile, expectedFileNotFound: true)
    }
    
    func testSimpleDownloadWorks() {
        let creds = DropboxCreds()!
        creds.accessToken = TestAccount.dropbox1.token()
        creds.accountId = TestAccount.dropbox1.id()
        
        downloadFile(creds: creds, cloudFileName: knownPresentFile)
    }
    
    func testDownloadWithRevokedToken() {
        let creds = DropboxCreds()!
        creds.accessToken = TestAccount.dropbox1Revoked.token()
        creds.accountId = TestAccount.dropbox1Revoked.id()
        
        downloadFile(creds: creds, cloudFileName: knownPresentFile, expectedRevokedToken: true)
    }
    
    func testSimpleDownloadWorks2() {
        let creds = DropboxCreds()!
        creds.accessToken = TestAccount.dropbox1.token()
        creds.accountId = TestAccount.dropbox1.id()
        
        downloadFile(creds: creds, cloudFileName: knownPresentFile2)
    }
    
    func testUploadAndDownloadWorks() {
        let deviceUUID = Foundation.UUID().uuidString
        let fileUUID = Foundation.UUID().uuidString
        
        let creds = DropboxCreds()!
        creds.accessToken = TestAccount.dropbox1.token()
        creds.accountId = TestAccount.dropbox1.id()

        let file = TestFile.test1
        guard case .string = file.contents else {
            XCTFail()
            return
        }
        
        let uploadRequest = UploadFileRequest()
        uploadRequest.fileUUID = fileUUID
        uploadRequest.mimeType = "text/plain"
        uploadRequest.fileVersion = 0
        uploadRequest.masterVersion = 1
        uploadRequest.sharingGroupUUID = UUID().uuidString
        uploadRequest.checkSum = file.dropboxCheckSum

        uploadFile(accountType: AccountScheme.dropbox.accountName, creds: creds, deviceUUID:deviceUUID, testFile: file, uploadRequest:uploadRequest)
        
        let cloudFileName = uploadRequest.cloudFileName(deviceUUID:deviceUUID, mimeType: uploadRequest.mimeType)
        Log.debug("cloudFileName: \(cloudFileName)")
        downloadFile(creds: creds, cloudFileName: cloudFileName, expectedStringFile: file)
    }
    
    func deleteFile(creds: DropboxCreds, cloudFileName: String, expectedFailure: Bool = false) {
        let exp = expectation(description: "\(#function)\(#line)")

        creds.deleteFile(cloudFileName: cloudFileName) { result in
            switch result {
            case .success:
                if expectedFailure {
                    XCTFail()
                }
            case .accessTokenRevokedOrExpired:
                XCTFail()
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
    
    func testDeletionWithRevokedAccessToken() {
        let creds = DropboxCreds()!
        creds.accessToken = TestAccount.dropbox1Revoked.token()
        creds.accountId = TestAccount.dropbox1Revoked.id()
        
        let existingFile = knownPresentFile
        
        let exp = expectation(description: "\(#function)\(#line)")

        creds.deleteFile(cloudFileName: existingFile) { result in
            switch result {
            case .success:
                XCTFail()
            case .accessTokenRevokedOrExpired:
                break
            case .failure:
                XCTFail()
            }

            exp.fulfill()
        }
        
        waitForExpectations(timeout: 10, handler: nil)
        
        let result = lookupFile(cloudFileName: existingFile)
        XCTAssert(result == true)
    }
    
    func testDeletionOfNonExistingFileFails() {
        let creds = DropboxCreds()!
        creds.accessToken = TestAccount.dropbox1.token()
        creds.accountId = TestAccount.dropbox1.id()
        deleteFile(creds: creds, cloudFileName: knownAbsentFile, expectedFailure: true)
    }

    func deletionOfExistingFile(file: TestFile, mimeType: MimeType) {
        let deviceUUID = Foundation.UUID().uuidString
        let fileUUID = Foundation.UUID().uuidString
        
        let creds = DropboxCreds()!
        creds.accessToken = TestAccount.dropbox1.token()
        creds.accountId = TestAccount.dropbox1.id()

        let uploadRequest = UploadFileRequest()
        uploadRequest.fileUUID = fileUUID
        uploadRequest.mimeType = mimeType.rawValue
        uploadRequest.fileVersion = 0
        uploadRequest.masterVersion = 1
        uploadRequest.sharingGroupUUID = UUID().uuidString
        uploadRequest.checkSum = file.dropboxCheckSum
        
        guard let fileName = uploadFile(accountType: AccountScheme.dropbox.accountName, creds: creds, deviceUUID:deviceUUID, testFile:file, uploadRequest:uploadRequest) else {
            XCTFail()
            return
        }
        
        deleteFile(creds: creds, cloudFileName: fileName)
    }
    
    func testDeletionOfExistingFileWorks() {
        deletionOfExistingFile(file: .test1, mimeType: .text)
    }
    
    func testDeletionOfExistingURLFileWorks() {
        deletionOfExistingFile(file: .testUrlFile, mimeType: .url)
    }
    
    func lookupFile(cloudFileName: String, expectError:Bool = false) -> Bool? {
        var foundResult: Bool?
        
        let creds = DropboxCreds()!
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
            case .failure, .accessTokenRevokedOrExpired:
                if !expectError {
                    XCTFail()
                }
            }
            
            exp.fulfill()
        }
        
        waitForExpectations(timeout: 10, handler: nil)
        return foundResult
    }
    
    func testLookupFileThatExists() {
        let result = lookupFile(cloudFileName: knownPresentFile)
        XCTAssert(result == true)
    }
    
    func testLookupFileThatDoesNotExist() {
        let result = lookupFile(cloudFileName: knownAbsentFile)
        XCTAssert(result == false)
    }
    
    func testLookupWithRevokedAccessToken() {
        let creds = DropboxCreds()!
        creds.accessToken = TestAccount.dropbox1Revoked.token()
        creds.accountId = TestAccount.dropbox1Revoked.id()
        
        let exp = expectation(description: "\(#function)\(#line)")
        
        creds.lookupFile(cloudFileName:knownPresentFile) { result in
            switch result {
            case .success, .failure:
                XCTFail()
            case .accessTokenRevokedOrExpired:
                break
            }
            
            exp.fulfill()
        }
        
        waitForExpectations(timeout: 10, handler: nil)
    }
}

extension FileDropboxTests {
    static var allTests : [(String, (FileDropboxTests) -> () throws -> Void)] {
        return [
            ("testCheckForFileFailsWithFileThatDoesNotExist", testCheckForFileFailsWithFileThatDoesNotExist),
            ("testCheckForFileWorksWithExistingFile", testCheckForFileWorksWithExistingFile),
            ("testUploadFileWorks", testUploadFileWorks),
            ("testUploadURLFileWorks", testUploadURLFileWorks),
            ("testUploadWithRevokedToken", testUploadWithRevokedToken),
            ("testFullUploadWorks", testFullUploadWorks),
            ("testFullUploadURLWorks", testFullUploadURLWorks),
            ("testDownloadOfNonExistingFileFails", testDownloadOfNonExistingFileFails),
            ("testSimpleDownloadWorks", testSimpleDownloadWorks),
            ("testDownloadWithRevokedToken", testDownloadWithRevokedToken),
            ("testSimpleDownloadWorks2", testSimpleDownloadWorks2),
            ("testUploadAndDownloadWorks", testUploadAndDownloadWorks),
            ("testDeletionWithRevokedAccessToken", testDeletionWithRevokedAccessToken),
            ("testDeletionOfNonExistingFileFails", testDeletionOfNonExistingFileFails),
            ("testDeletionOfExistingFileWorks", testDeletionOfExistingFileWorks),
            ("testDeletionOfExistingURLFileWorks", testDeletionOfExistingURLFileWorks),
            ("testLookupFileThatDoesNotExist", testLookupFileThatDoesNotExist),
            ("testLookupFileThatExists", testLookupFileThatExists),
            ("testLookupWithRevokedAccessToken", testLookupWithRevokedAccessToken)
        ]
    }
    
    func testLinuxTestSuiteIncludesAllTests() {
        linuxTestSuiteIncludesAllTests(testType:FileDropboxTests.self)
    }
}

