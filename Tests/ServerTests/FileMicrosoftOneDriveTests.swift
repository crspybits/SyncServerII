//
//  FileMicrosoftTests.swift
//  ServerTests
//
//  Created by Christopher G Prince on 9/13/19.
//


import XCTest
@testable import Server
import Foundation
import LoggerAPI
import HeliumLogger
import SyncServerShared

class FileMicrosftOneDriveTests: ServerTestCase, LinuxTestable {
    // In my OneDrive:
    let knownPresentFile = "DO-NOT-REMOVE.txt"

    let knownAbsentFile = "Markwa.Farkwa.Blarkwa"

    override func setUp() {
        super.setUp()
    }
    
    override func tearDown() {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
        super.tearDown()
    }

    func testCheckForFileFailsWithFileThatDoesNotExist() {
        let creds = MicrosoftCreds()
        creds.refreshToken = TestAccount.microsoft1.token()
        
        let exp = expectation(description: "\(#function)\(#line)")
        creds.refresh() { error in
            guard error == nil else {
                XCTFail()
                exp.fulfill()
                return
            }
            
            creds.checkForFile(fileName: self.knownAbsentFile) { result in
                switch result {
                case .success(.fileNotFound):
                    break
                case .success(.fileFound):
                    XCTFail()
                case .failure:
                    XCTFail()
                case .accessTokenRevokedOrExpired:
                    XCTFail()
                }

                exp.fulfill()
            }
        }
        
        waitForExpectations(timeout: 10, handler: nil)
    }
    
    func testCheckForFileFailsWithExpiredAccessToken() {
        let creds = MicrosoftCreds()
        creds.accessToken = TestAccount.microsoft1ExpiredAccessToken.secondToken()

        let existingFile = self.knownPresentFile
        
        let exp = expectation(description: "\(#function)\(#line)")
        
        creds.checkForFile(fileName: existingFile) { result in
            switch result {
            case .success(.fileFound):
                XCTFail()
            case .success((.fileNotFound)):
                XCTFail()
            case .failure:
                XCTFail()
            case .accessTokenRevokedOrExpired:
                break
            }

            exp.fulfill()
        }
        
        waitForExpectations(timeout: 10, handler: nil)
    }
    
    func testCheckForFileWorksWithExistingFile() {
        let creds = MicrosoftCreds()
        creds.refreshToken = TestAccount.microsoft1.token()
        
        //let existingFile = "539C70F7-8144-49F1-81C7-003DD5D8833B.14B026F1-6E5F-43E6-A54B-0524BB8F3E9C.0.txt"
        let existingFile = self.knownPresentFile
        
        let exp = expectation(description: "\(#function)\(#line)")
        creds.refresh() { error in
            guard error == nil else {
                XCTFail()
                exp.fulfill()
                return
            }
            
            creds.checkForFile(fileName: existingFile) { result in
                switch result {
                case .success(.fileFound):
                    break
                case .success((.fileNotFound)):
                    XCTFail()
                case .failure, .accessTokenRevokedOrExpired:
                    XCTFail()
                }

                exp.fulfill()
            }
        }
        
        waitForExpectations(timeout: 10, handler: nil)
    }
    
    func uploadFile(file: TestFile) {
        let ext = Extension.forMimeType(mimeType: file.mimeType.rawValue)
        let fileName = Foundation.UUID().uuidString + ".\(ext)"
        
        let creds = MicrosoftCreds()
        creds.refreshToken = TestAccount.microsoft1.token()
        
        let exp = expectation(description: "\(#function)\(#line)")
        
        creds.refresh() { error in
            guard error == nil else {
                XCTFail()
                exp.fulfill()
                return
            }
            
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
            
            creds.uploadFile(withName: fileName, mimeType: file.mimeType, data: fileContentsData) { result in
                switch result {
                case .success(let hash):
                    XCTAssert(hash == file.sha1Hash)
                case .failure(let error):
                    Log.error("uploadFile: \(error)")
                    XCTFail()
                case .accessTokenRevokedOrExpired:
                    XCTFail()
                }
                
                exp.fulfill()
            }
        }
        
        waitForExpectations(timeout: 10, handler: nil)
    }
    
    func testSimpleUploadWithExpiredAccessToken() {
        let file = TestFile.test1
        let ext = Extension.forMimeType(mimeType: file.mimeType.rawValue)
        let fileName = Foundation.UUID().uuidString + ".\(ext)"
        
        let creds = MicrosoftCreds()
        creds.accessToken = TestAccount.microsoft1ExpiredAccessToken.secondToken()
        
        let exp = expectation(description: "\(#function)\(#line)")
            
        let fileContentsData: Data

        switch file.contents {
        case .string(let fileContents):
            fileContentsData = fileContents.data(using: .ascii)!
        case .url(let url):
            fileContentsData = try! Data(contentsOf: url)
        }
        
        creds.uploadFile(withName: fileName, mimeType: file.mimeType, data: fileContentsData) { result in
            switch result {
            case .success:
                XCTFail()
            case .failure:
                XCTFail()
            case .accessTokenRevokedOrExpired:
                break
            }
            
            exp.fulfill()
        }
        
        waitForExpectations(timeout: 10, handler: nil)
    }
    
    func testUploadTextFileWorks() {
        uploadFile(file: .test1)
    }
    
    func testUploadImageFileWorks() {
        uploadFile(file: .catJpg)
    }
    
    func testUploadURLFileWorks() {
        uploadFile(file: .testUrlFile)
    }
    
    /* For Microsoft: What we need here is to--
        1) For a different account, say .microsoft2,
        2) generate an access token from a refresh token
        3) then revoke access from the account for the app
        4) use the access token below
        However, will the test fail because of the revocation or just because of expiry of the access token?
    */
    // func testUploadWithRevokedToken() {
    // }
    
     func testUploadWithExpiredToken() {
        let deviceUUID = Foundation.UUID().uuidString
        let fileUUID = Foundation.UUID().uuidString
        
        let creds = MicrosoftCreds()
        creds.accessToken = TestAccount.microsoft1ExpiredAccessToken.secondToken()
        
        let file = TestFile.test1
            
        let uploadRequest = UploadFileRequest()
        uploadRequest.fileUUID = fileUUID
        uploadRequest.mimeType = file.mimeType.rawValue
        uploadRequest.fileVersion = 0
        uploadRequest.masterVersion = 1
        uploadRequest.sharingGroupUUID = UUID().uuidString
        uploadRequest.checkSum = file.sha1Hash
        
        let options = CloudStorageFileNameOptions(cloudFolderName: nil, mimeType: file.mimeType.rawValue)

        self.uploadFile(accountType: AccountScheme.microsoft.accountName, creds: creds, deviceUUID:deviceUUID, testFile: file, uploadRequest:uploadRequest, options: options, failureExpected: true, expectAccessTokenRevokedOrExpired: true)
     }
    
    func fullUpload(file: TestFile) {
        let deviceUUID = Foundation.UUID().uuidString
        let fileUUID = Foundation.UUID().uuidString
        
        let creds = MicrosoftCreds()
        creds.refreshToken = TestAccount.microsoft1.token()
        
        refresh(creds: creds) { success in
            guard success else {
                XCTFail()
                return
            }
            
            let uploadRequest = UploadFileRequest()
            uploadRequest.fileUUID = fileUUID
            uploadRequest.mimeType = file.mimeType.rawValue
            uploadRequest.fileVersion = 0
            uploadRequest.masterVersion = 1
            uploadRequest.sharingGroupUUID = UUID().uuidString
            uploadRequest.checkSum = file.sha1Hash
            
            let options = CloudStorageFileNameOptions(cloudFolderName: nil, mimeType: file.mimeType.rawValue)
            
            self.uploadFile(accountType: AccountScheme.microsoft.accountName, creds: creds, deviceUUID:deviceUUID, testFile: file, uploadRequest:uploadRequest, options: options)
            
            // The second time we try it, it should fail with CloudStorageError.alreadyUploaded -- same file.
            self.uploadFile(accountType: AccountScheme.microsoft.accountName, creds: creds, deviceUUID:deviceUUID, testFile: file, uploadRequest:uploadRequest,options: options, failureExpected: true, errorExpected: CloudStorageError.alreadyUploaded)
        }
    }
    
    func refresh(creds: MicrosoftCreds, completion:@escaping (Bool)->()) {
        let exp = expectation(description: "full upload")
        
        creds.refresh() { error in
            guard error == nil else {
                XCTFail()
                exp.fulfill()
                completion(false)
                return
            }
            
            exp.fulfill()
        }

        waitForExpectations(timeout: 10, handler: nil)
        completion(true)
    }
    
    func testFullUploadWorks() {
        fullUpload(file: .test1)
    }
    
    func testFullImageUploadWorks() {
        fullUpload(file: .catJpg)
    }
    
    func testFullUploadURLWorks() {
        fullUpload(file: .testUrlFile)
    }
    
    func downloadFile(creds: MicrosoftCreds, cloudFileName: String, expectedStringFile:TestFile? = nil, expectedFailure: Bool = false, expectedFileNotFound: Bool = false, expectedRevokedToken: Bool = false) {
        let exp = expectation(description: "\(#function)\(#line)")

        creds.downloadFile(cloudFileName: cloudFileName, options: nil) { result in
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
                    
                    XCTAssert(downloadResult.checkSum == expectedStringFile.sha1Hash)
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
        let creds = MicrosoftCreds()
        creds.refreshToken = TestAccount.microsoft1.token()
        refresh(creds: creds) { success in
            guard success else {
                XCTFail()
                return
            }
            
            self.downloadFile(creds: creds, cloudFileName: self.knownAbsentFile, expectedFileNotFound: true)
        }
    }
    
    // Download without checksum.
    func testSimpleDownloadWorks() {
        let creds = MicrosoftCreds()
        creds.refreshToken = TestAccount.microsoft1.token()
        refresh(creds: creds) { success in
            guard success else {
                XCTFail()
                return
            }
            
            let exp = self.expectation(description: "download")
            creds.downloadFile(cloudFileName: self.knownPresentFile) { result in
                switch result {
                case .success:
                    break
                case .failure:
                    XCTFail()
                case .accessTokenRevokedOrExpired:
                    XCTFail()
                }
                exp.fulfill()
            }
            self.waitExpectation(timeout: 10, handler: nil)
        }
    }
    
    func testSimpleDownloadWithExpiredAccessTokenFails() {
        let creds = MicrosoftCreds()
        creds.accessToken = TestAccount.microsoft1ExpiredAccessToken.secondToken()

        let exp = self.expectation(description: "download")
        creds.downloadFile(cloudFileName: self.knownPresentFile) { result in
            switch result {
            case .success:
                XCTFail()
            case .failure:
                XCTFail()
            case .accessTokenRevokedOrExpired:
                break
            }
            exp.fulfill()
        }
        self.waitExpectation(timeout: 10, handler: nil)
    }
    
    // See above for revoked token test conditions
    // func testDownloadWithRevokedToken() {
    // }
    
    func testUploadAndDownloadWorks() {
        let deviceUUID = Foundation.UUID().uuidString
        let fileUUID = Foundation.UUID().uuidString
        
        let creds = MicrosoftCreds()
        creds.refreshToken = TestAccount.microsoft1.token()

        let file = TestFile.test1
        guard case .string = file.contents else {
            XCTFail()
            return
        }
        
        let uploadRequest = UploadFileRequest()
        uploadRequest.fileUUID = fileUUID
        uploadRequest.mimeType = file.mimeType.rawValue
        uploadRequest.fileVersion = 0
        uploadRequest.masterVersion = 1
        uploadRequest.sharingGroupUUID = UUID().uuidString
        uploadRequest.checkSum = file.sha1Hash
        
        let options = CloudStorageFileNameOptions(cloudFolderName: nil, mimeType: file.mimeType.rawValue)
        
        refresh(creds: creds) { success in
            guard success else {
                XCTFail()
                return
            }
            
            guard let _ = self.uploadFile(accountType: AccountScheme.microsoft.accountName, creds: creds, deviceUUID:deviceUUID, testFile: file, uploadRequest:uploadRequest, options: options) else {
                XCTFail()
                return
            }
            
            let cloudFileName = uploadRequest.cloudFileName(deviceUUID:deviceUUID, mimeType: uploadRequest.mimeType)
            Log.debug("cloudFileName: \(cloudFileName)")
            self.downloadFile(creds: creds, cloudFileName: cloudFileName, expectedStringFile: file)
        }
    }
    
    // Doesn't refresh the creds first.
    func deleteFile(creds: MicrosoftCreds, cloudFileName: String, expectedFailure: Bool = false) {
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
    
    // See above for comments on revoked token
    //func testDeletionWithRevokedAccessToken() {
    //}
    
    func testDeletionOfNonExistingFileFails() {
        let creds = MicrosoftCreds()
        creds.refreshToken = TestAccount.microsoft1.token()
        
        refresh(creds: creds) { success in
            guard success else {
                XCTFail()
                return
            }
            
            self.deleteFile(creds: creds, cloudFileName: self.knownAbsentFile, expectedFailure: true)
        }
    }

    func deletionOfExistingFile(file: TestFile) {
        let deviceUUID = Foundation.UUID().uuidString
        let fileUUID = Foundation.UUID().uuidString
        
        let creds = MicrosoftCreds()
        creds.refreshToken = TestAccount.microsoft1.token()

        let uploadRequest = UploadFileRequest()
        uploadRequest.fileUUID = fileUUID
        uploadRequest.mimeType = file.mimeType.rawValue
        uploadRequest.fileVersion = 0
        uploadRequest.masterVersion = 1
        uploadRequest.sharingGroupUUID = UUID().uuidString
        uploadRequest.checkSum = file.sha1Hash
        
        let options = CloudStorageFileNameOptions(cloudFolderName: nil, mimeType: file.mimeType.rawValue)
        
        refresh(creds: creds) { success in
            guard success else {
                XCTFail()
                return
            }
            
            guard let fileName = self.uploadFile(accountType: AccountScheme.microsoft.accountName, creds: creds, deviceUUID:deviceUUID, testFile:file, uploadRequest:uploadRequest, options: options) else {
                XCTFail()
                return
            }
            
            self.deleteFile(creds: creds, cloudFileName: fileName)
        }
    }
    
    func testSimpleDeletionWithExpiredAccessTokenFails() {
        // First need to get item id of the file in the normal way so it doesn't fail.
        
        let creds = MicrosoftCreds()
        creds.refreshToken = TestAccount.microsoft1.token()
        
        refresh(creds: creds) { success in
            guard success else {
                XCTFail()
                return
            }
            
            let exp = self.expectation(description: "delete")
            
            creds.checkForFile(fileName: self.knownPresentFile) { result in
                switch result {
                case .success(.fileFound(let checkResult)):
                    self.deleteExpectingExpiredAccessToken(itemId: checkResult.id, expectation: exp)
                case .success(.fileNotFound):
                    XCTFail()
                    exp.fulfill()
                case .accessTokenRevokedOrExpired, .failure:
                    XCTFail()
                    exp.fulfill()
                }
            }
            
            self.waitForExpectations(timeout: 10, handler: nil)
        }
    }
    
    func deleteExpectingExpiredAccessToken(itemId: String, expectation: XCTestExpectation) {
        let creds = MicrosoftCreds()
        creds.accessToken = TestAccount.microsoft1ExpiredAccessToken.secondToken()
        
        creds.deleteFile(itemId: itemId) { result in
            switch result {
            case .success:
                XCTFail()
            case .failure:
                XCTFail()
            case .accessTokenRevokedOrExpired:
                break
            }
            
            expectation.fulfill()
        }
    }
    
    func testDeletionOfExistingFileWorks() {
        deletionOfExistingFile(file: .test1)
    }
    
    func testDeletionOfExistingURLFileWorks() {
        deletionOfExistingFile(file: .testUrlFile)
    }
    
    func lookupFile(cloudFileName: String, expectError:Bool = false) {
        let creds = MicrosoftCreds()
        creds.refreshToken = TestAccount.microsoft1.token()
        
        refresh(creds: creds) { success in
            guard success else {
                XCTFail()
                return
            }

            let exp = self.expectation(description: "\(#function)\(#line)")
            
            creds.lookupFile(cloudFileName:cloudFileName, options: nil) { result in
                switch result {
                case .success:
                    if expectError {
                        XCTFail()
                    }
                case .failure, .accessTokenRevokedOrExpired:
                    if !expectError {
                        XCTFail()
                    }
                }
                
                exp.fulfill()
            }
            
            self.waitForExpectations(timeout: 10, handler: nil)
        }
    }
    
    func testLookupFileThatExists() {
        lookupFile(cloudFileName: knownPresentFile)
    }
    
    func testLookupFileThatDoesNotExist() {
        lookupFile(cloudFileName: knownAbsentFile)
    }
    
    // See comments for revoked access token
    // func testLookupWithRevokedAccessToken() {
    // }
}

extension FileMicrosftOneDriveTests {
    static var allTests : [(String, (FileMicrosftOneDriveTests) -> () throws -> Void)] {
        return [
            ("testCheckForFileFailsWithFileThatDoesNotExist", testCheckForFileFailsWithFileThatDoesNotExist),
            ("testCheckForFileWorksWithExistingFile", testCheckForFileWorksWithExistingFile),
            ("testUploadTextFileWorks", testUploadTextFileWorks),
            ("testUploadImageFileWorks", testUploadImageFileWorks),
            ("testUploadURLFileWorks", testUploadURLFileWorks),
            //("testUploadWithRevokedToken", testUploadWithRevokedToken),
            ("testFullUploadWorks", testFullUploadWorks),
            ("testFullImageUploadWorks", testFullImageUploadWorks),
            ("testFullUploadURLWorks", testFullUploadURLWorks),
            ("testDownloadOfNonExistingFileFails", testDownloadOfNonExistingFileFails),
            ("testSimpleDownloadWorks", testSimpleDownloadWorks),
            //("testDownloadWithRevokedToken", testDownloadWithRevokedToken),
            ("testUploadAndDownloadWorks", testUploadAndDownloadWorks),
            //("testDeletionWithRevokedAccessToken", testDeletionWithRevokedAccessToken),
            ("testDeletionOfNonExistingFileFails", testDeletionOfNonExistingFileFails),
            ("testDeletionOfExistingFileWorks", testDeletionOfExistingFileWorks),
            ("testDeletionOfExistingURLFileWorks", testDeletionOfExistingURLFileWorks),
            ("testLookupFileThatDoesNotExist", testLookupFileThatDoesNotExist),
            ("testLookupFileThatExists", testLookupFileThatExists),
            // ("testLookupWithRevokedAccessToken", testLookupWithRevokedAccessToken)
            ("testUploadWithExpiredToken", testUploadWithExpiredToken),
            ("testCheckForFileFailsWithExpiredAccessToken", testCheckForFileFailsWithExpiredAccessToken),
            ("testSimpleDownloadWithExpiredAccessTokenFails", testSimpleDownloadWithExpiredAccessTokenFails),
            ("testSimpleDeletionWithExpiredAccessTokenFails", testSimpleDeletionWithExpiredAccessTokenFails)
        ]
    }
    
    func testLinuxTestSuiteIncludesAllTests() {
        linuxTestSuiteIncludesAllTests(testType:FileMicrosftOneDriveTests.self)
    }
}

