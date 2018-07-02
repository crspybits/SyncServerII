//
//  GoogleDriveTests.swift
//  Server
//
//  Created by Christopher Prince on 1/7/17.
//
//

import XCTest
@testable import Server
import Foundation
import HeliumLogger
import LoggerAPI
import SyncServerShared

class GoogleDriveTests: ServerTestCase, LinuxTestable {
    // In my Google Drive, at the top-level:
    let knownPresentFolder = "Programming"
    let knownPresentFile = "DO-NOT-REMOVE.txt"

    // This is special in that (a) it contains only two characters, and (b) it was causing me problems for downloading on 2/4/18.
    let knownPresentFile2 = "DO-NOT-REMOVE2.txt"
    
    let knownAbsentFolder = "Markwa.Farkwa.Blarkwa"
    let knownAbsentFile = "Markwa.Farkwa.Blarkwa"

    // Folder that will be created and removed.
    let folderCreatedAndDeleted = "abcdefg12345temporary"

    override func setUp() {
        super.setUp()
    }
    
    override func tearDown() {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
        super.tearDown()
    }

    func testListFiles() {
        let creds = GoogleCreds()
        creds.refreshToken = TestAccount.google1.token()
        let exp = expectation(description: "\(#function)\(#line)")
        
        creds.refresh { error in
            XCTAssert(error == nil)
            XCTAssert(creds.accessToken != nil)
            
            creds.listFiles { json, error in
                XCTAssert(error == nil)
                XCTAssert((json?.count)! > 0)
                exp.fulfill()
            }
        }

        waitForExpectations(timeout: 10, handler: nil)
    }
    
    func searchForFolder(name:String, presentExpected:Bool) {
        let creds = GoogleCreds()
        creds.refreshToken = TestAccount.google1.token()
        let exp = expectation(description: "\(#function)\(#line)")
        
        creds.refresh { error in
            XCTAssert(error == nil)
            XCTAssert(creds.accessToken != nil)
            
            creds.searchFor(.folder, itemName: name) { result, error in
                if presentExpected {
                    XCTAssert(result != nil)
                }
                else {
                    XCTAssert(result == nil)
                }
                XCTAssert(error == nil)
                exp.fulfill()
            }
        }

        waitForExpectations(timeout: 10, handler: nil)
    }
    
    func searchForFile(name:String, withMimeType mimeType:String, inFolder folderName:String?, presentExpected:Bool) {
        let creds = GoogleCreds()
        creds.refreshToken = TestAccount.google1.token()
        let exp = expectation(description: "\(#function)\(#line)")
        
        func searchForFile(parentFolderId:String?) {
            creds.searchFor(.file(mimeType:mimeType, parentFolderId:parentFolderId), itemName: name) { result, error in
                if presentExpected {
                    XCTAssert(result != nil)
                }
                else {
                    XCTAssert(result == nil)
                }
                XCTAssert(error == nil)
                exp.fulfill()
            }
        }
        
        creds.refresh { error in
            XCTAssert(error == nil)
            XCTAssert(creds.accessToken != nil)
            
            if folderName == nil {
                searchForFile(parentFolderId: nil)
            }
            else {
                creds.searchFor(.folder, itemName: folderName!) { result, error in
                    XCTAssert(result != nil)
                    XCTAssert(error == nil)
                    searchForFile(parentFolderId: result!.itemId)
                }
            }
        }

        waitForExpectations(timeout: 20, handler: nil)
    }
    
    func testSearchForPresentFolder() {
        searchForFolder(name: self.knownPresentFolder, presentExpected: true)
    }
    
    func testSearchForAbsentFolder() {
        searchForFolder(name: self.knownAbsentFolder, presentExpected: false)
    }
    
    func testSearchForPresentFile() {
        searchForFile(name: knownPresentFile, withMimeType: "text/plain", inFolder: nil, presentExpected: true)
    }
    
    func testSearchForAbsentFile() {
        searchForFile(name: knownAbsentFile, withMimeType: "text/plain", inFolder: nil, presentExpected: false)
    }
    
    func testSearchForPresentFileInFolder() {
        searchForFile(name: knownPresentFile, withMimeType: "text/plain", inFolder: knownPresentFolder, presentExpected: true)
    }
    
    func testSearchForAbsentFileInFolder() {
        searchForFile(name: knownAbsentFile, withMimeType: "text/plain", inFolder: knownPresentFolder, presentExpected: false)
    }
    
    // Haven't been able to get trashFile to work yet.
/*
    func testTrashFolder() {
        let creds = GoogleCreds()
        creds.refreshToken = self.credentialsToken()
        let exp = expectation(description: "\(#function)\(#line)")
        
        creds.refresh { error in
            XCTAssert(error == nil)
            XCTAssert(creds.accessToken != nil)
            
//            creds.createFolder(folderName: "TestMe") { folderId, error in
//                XCTAssert(folderId != nil)
//                XCTAssert(error == nil)
            
                let folderId = "0B3xI3Shw5ptRdWtPR3ZLdXpqbHc"
                creds.trashFile(fileId: folderId) { error in
                    XCTAssert(error == nil)
                    exp.fulfill()
                }
//            }
        }

        waitForExpectations(timeout: 10, handler: nil)
    }
*/

    func testCreateAndDeleteFolder() {
        let creds = GoogleCreds()
        creds.refreshToken = TestAccount.google1.token()
        let exp = expectation(description: "\(#function)\(#line)")
        
        creds.refresh { error in
            XCTAssert(error == nil)
            XCTAssert(creds.accessToken != nil)
            
            creds.createFolder(rootFolderName: "TestMe") { folderId, error in
                XCTAssert(folderId != nil)
                XCTAssert(error == nil)
            
                creds.deleteFile(fileId: folderId!) { error in
                    XCTAssert(error == nil)
                    exp.fulfill()
                }
            }
        }

        waitForExpectations(timeout: 10, handler: nil)
    }
    
    func testDeleteFolderThatDoesNotExistFailure() {
        let creds = GoogleCreds()
        creds.refreshToken = TestAccount.google1.token()
        let exp = expectation(description: "\(#function)\(#line)")
        
        creds.refresh { error in
            XCTAssert(error == nil)
            XCTAssert(creds.accessToken != nil)
            
            creds.deleteFile(fileId: "foobar") { error in
                XCTAssert(error != nil)
                exp.fulfill()
            }
        }

        waitForExpectations(timeout: 10, handler: nil)
    }
    
    func testCreateFolderIfDoesNotExist() {
        let creds = GoogleCreds()
        creds.refreshToken = TestAccount.google1.token()
        let exp = expectation(description: "\(#function)\(#line)")
        
        creds.refresh { error in
            XCTAssert(error == nil)
            XCTAssert(creds.accessToken != nil)
            
            creds.createFolderIfDoesNotExist(rootFolderName: self.folderCreatedAndDeleted) { (folderIdA, error) in
                XCTAssert(folderIdA != nil)
                XCTAssert(error == nil)
                
                // It should be there after being created.
                creds.searchFor(.folder, itemName: self.folderCreatedAndDeleted) { (result, error) in
                    
                    XCTAssert(result != nil)
                    XCTAssert(error == nil)
                    
                    // And attempting to create it again shouldn't fail.
                    creds.createFolderIfDoesNotExist(rootFolderName: self.folderCreatedAndDeleted) { (folderIdB, error) in
                        XCTAssert(folderIdB != nil)
                        XCTAssert(error == nil)
                        XCTAssert(folderIdA == folderIdB)
                        
                        creds.deleteFile(fileId: folderIdA!) { error in
                            XCTAssert(error == nil)
                            exp.fulfill()
                        }
                    }
                }
            }
        }

        waitForExpectations(timeout: 10, handler: nil)
    }
    
    func testFullUploadWorks() {
        let creds = GoogleCreds()
        creds.refreshToken = TestAccount.google1.token()
        let exp = expectation(description: "\(#function)\(#line)")
        
        creds.refresh { error in
            XCTAssert(error == nil)
            XCTAssert(creds.accessToken != nil)
            exp.fulfill()
        }

        waitForExpectations(timeout: 10, handler: nil)
        
        // Do the upload
        let deviceUUID = Foundation.UUID().uuidString
        let fileUUID = Foundation.UUID().uuidString
        
        let fileContents = "Hello World"

        let uploadRequest = UploadFileRequest(json: [
            UploadFileRequest.fileUUIDKey : fileUUID,
            UploadFileRequest.mimeTypeKey: "text/plain",
            UploadFileRequest.fileVersionKey: 0,
            UploadFileRequest.masterVersionKey: 1,
            ServerEndpoint.sharingGroupIdKey: 0
        ])!
        
        let options = CloudStorageFileNameOptions(cloudFolderName: self.knownPresentFolder, mimeType: "text/plain")
        
        uploadFile(creds: creds, deviceUUID:deviceUUID, fileContents:fileContents, uploadRequest:uploadRequest, options: options)
        
        // The second time we try it, it should fail with CloudStorageError.alreadyUploaded -- same file.
        uploadFile(creds: creds, deviceUUID:deviceUUID, fileContents:fileContents, uploadRequest:uploadRequest, options: options, failureExpected: true, errorExpected: CloudStorageError.alreadyUploaded)
    }
    
    func downloadFile(cloudFileName:String, expectError:Bool = false) {
        let creds = GoogleCreds()
        creds.refreshToken = TestAccount.google1.token()
        let exp = expectation(description: "\(#function)\(#line)")
        
        creds.refresh { error in
            XCTAssert(error == nil)
            XCTAssert(creds.accessToken != nil)
            
            let options = CloudStorageFileNameOptions(cloudFolderName: self.knownPresentFolder, mimeType: "text/plain")
            
            creds.downloadFile(cloudFileName: cloudFileName, options:options) { result in
                switch result {
                case .success:
                    if expectError {
                        XCTFail()
                    }
                case .failure:
                    if !expectError {
                        XCTFail()
                    }
                }

                // A different unit test will check to see if the contents of the file are correct.
                
                exp.fulfill()
            }
        }
        
        waitForExpectations(timeout: 10, handler: nil)
    }
    
    func testBasicFileDownloadWorks() {
        downloadFile(cloudFileName: self.knownPresentFile)
    }
    
    func testSearchForPresentFile2() {
        searchForFile(name: knownPresentFile2, withMimeType: "text/plain", inFolder: nil, presentExpected: true)
    }
    
    func testBasicFileDownloadWorks2() {
        downloadFile(cloudFileName: self.knownPresentFile2)
    }
    
    func testFileDownloadOfNonExistentFileFails() {
        downloadFile(cloudFileName: self.knownAbsentFile, expectError: true)
    }
    
    func testThatAccessTokenRefreshOccursWithBadToken() {
        let creds = GoogleCreds()
        creds.refreshToken = TestAccount.google1.token()
        let exp = expectation(description: "\(#function)\(#line)")
        
        // Use a known incorrect access token. We expect this to generate a 401 unauthorized, and thus cause an access token refresh.
        creds.accessToken = "foobar"
        
        let options = CloudStorageFileNameOptions(cloudFolderName: self.knownPresentFolder, mimeType: "text/plain")
        
        creds.downloadFile(cloudFileName: self.knownPresentFile, options:options) { result in
            switch result {
            case .success:
                break
            case .failure:
                XCTFail()
            }
            
            exp.fulfill()
        }
        
        waitForExpectations(timeout: 10, handler: nil)
    }
    
    func lookupFile(cloudFileName: String, expectError:Bool = false) -> Bool? {
        var foundResult: Bool?
        
        let creds = GoogleCreds()
        creds.refreshToken = TestAccount.google1.token()
        let exp = expectation(description: "\(#function)\(#line)")
        
        creds.refresh { error in
            XCTAssert(error == nil)
            XCTAssert(creds.accessToken != nil)
            
            let options = CloudStorageFileNameOptions(cloudFolderName: self.knownPresentFolder, mimeType: "text/plain")
            
            creds.lookupFile(cloudFileName:cloudFileName, options:options) { result in
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

extension GoogleDriveTests {
    static var allTests : [(String, (GoogleDriveTests) -> () throws -> Void)] {
        return [
            ("testListFiles", testListFiles),
            ("testSearchForPresentFolder", testSearchForPresentFolder),
            ("testSearchForAbsentFolder", testSearchForAbsentFolder),
            ("testSearchForPresentFile", testSearchForPresentFile),
            ("testSearchForAbsentFile", testSearchForAbsentFile),
            ("testSearchForPresentFileInFolder", testSearchForPresentFileInFolder),
            ("testSearchForAbsentFileInFolder", testSearchForAbsentFileInFolder),
            ("testCreateAndDeleteFolder", testCreateAndDeleteFolder),
            ("testDeleteFolderThatDoesNotExistFailure", testDeleteFolderThatDoesNotExistFailure),
            ("testCreateFolderIfDoesNotExist", testCreateFolderIfDoesNotExist),
            ("testFullUploadWorks", testFullUploadWorks),
            ("testBasicFileDownloadWorks", testBasicFileDownloadWorks),
            ("testSearchForPresentFile2", testSearchForPresentFile2),
            ("testBasicFileDownloadWorks2", testBasicFileDownloadWorks2),
            ("testFileDownloadOfNonExistentFileFails", testFileDownloadOfNonExistentFileFails),
            ("testThatAccessTokenRefreshOccursWithBadToken", testThatAccessTokenRefreshOccursWithBadToken),
            ("testLookupFileThatDoesNotExist", testLookupFileThatDoesNotExist),
            ("testLookupFileThatExists", testLookupFileThatExists)
        ]
    }
    
    func testLinuxTestSuiteIncludesAllTests() {
        linuxTestSuiteIncludesAllTests(testType:GoogleDriveTests.self)
    }
}

