//
//  FileControllerTests.swift
//  Server
//
//  Created by Christopher Prince on 1/15/17.
//
//

import XCTest
@testable import Server
import LoggerAPI
import Foundation
import SyncServerShared

class FileControllerTests: ServerTestCase, LinuxTestable {

    override func setUp() {
        super.setUp()
    }
    
    override func tearDown() {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
        super.tearDown()
    }
      
    // A test that causes a conflict with the master version on the server. Presumably this needs to take the form of (a) device1 uploading a file to the server, (b) device2 uploading a file, and finishing that upload (`DoneUploads` endpoint), and (c) device1 uploading a second file using its original master version.
    func testMasterVersionConflict1() {
        let deviceUUID1 = Foundation.UUID().uuidString
        guard let uploadResult = uploadTextFile(deviceUUID:deviceUUID1), let sharingGroupUUID = uploadResult.sharingGroupUUID else {
            XCTFail()
            return
        }
        
        let deviceUUID2 = Foundation.UUID().uuidString
        guard let _ = uploadTextFile(deviceUUID:deviceUUID2, addUser:.no(sharingGroupUUID: sharingGroupUUID)) else {
            XCTFail()
            return
        }
        
        self.sendDoneUploads(expectedNumberOfUploads: 1, deviceUUID:deviceUUID2, sharingGroupUUID: sharingGroupUUID)
        
        guard let _ = uploadTextFile(deviceUUID:deviceUUID2, addUser:.no(sharingGroupUUID: sharingGroupUUID), updatedMasterVersionExpected:1) else {
            XCTFail()
            return
        }
    }
    
    func testMasterVersionConflict2() {
        let deviceUUID1 = Foundation.UUID().uuidString
        guard let uploadResult = uploadTextFile(deviceUUID:deviceUUID1), let sharingGroupUUID = uploadResult.sharingGroupUUID else {
            XCTFail()
            return
        }
        
        let deviceUUID2 = Foundation.UUID().uuidString
        guard let _ = uploadTextFile(deviceUUID:deviceUUID2, addUser:.no(sharingGroupUUID: sharingGroupUUID)) else {
            XCTFail()
            return
        }
        
        self.sendDoneUploads(expectedNumberOfUploads: 1, deviceUUID:deviceUUID1, sharingGroupUUID: sharingGroupUUID)
        
        // No uploads should have been successfully finished, i.e., expectedNumberOfUploads = nil, and the updatedMasterVersion should have been updated to 1.
        self.sendDoneUploads(expectedNumberOfUploads: nil, deviceUUID:deviceUUID2, updatedMasterVersionExpected:1, sharingGroupUUID: sharingGroupUUID)
    }

    func testIndexWithNoFiles() {
        let deviceUUID = Foundation.UUID().uuidString
        let sharingGroupUUID = Foundation.UUID().uuidString

        guard let _ = self.addNewUser(sharingGroupUUID: sharingGroupUUID, deviceUUID:deviceUUID) else {
            XCTFail()
            return
        }
        
        self.getIndex(expectedFiles: [], masterVersionExpected: 0, sharingGroupUUID: sharingGroupUUID)
    }
    
    func testGetIndexForOnlySharingGroupsWorks() {
        let deviceUUID = Foundation.UUID().uuidString
        let sharingGroupUUID = Foundation.UUID().uuidString

        guard let _ = addNewUser(sharingGroupUUID: sharingGroupUUID, deviceUUID:deviceUUID) else {
            XCTFail()
            return
        }
        
        guard let (files, sharingGroups) = getIndex() else {
            XCTFail()
            return
        }
        
        XCTAssert(files == nil)
        
        guard sharingGroups.count == 1 else {
            XCTFail()
            return
        }
        
        XCTAssert(sharingGroups[0].sharingGroupUUID == sharingGroupUUID)
        XCTAssert(sharingGroups[0].sharingGroupName == nil)
        XCTAssert(sharingGroups[0].deleted == false)
        guard sharingGroups[0].sharingGroupUsers != nil, sharingGroups[0].sharingGroupUsers.count == 1 else {
            XCTFail()
            return
        }
        
        sharingGroups[0].sharingGroupUsers.forEach { sgu in
            XCTAssert(sgu.name != nil)
            XCTAssert(sgu.userId != nil)
        }
    }
    
    func testIndexWithOneFile() {
        let deviceUUID = Foundation.UUID().uuidString
        let testAccount:TestAccount = .primaryOwningAccount
        
        guard let uploadResult = uploadTextFile(testAccount: testAccount, deviceUUID:deviceUUID),
            let sharingGroupUUID = uploadResult.sharingGroupUUID else {
            XCTFail()
            return
        }
        
        // Have to do a DoneUploads to transfer the files into the FileIndex
        self.sendDoneUploads(expectedNumberOfUploads: 1, deviceUUID:deviceUUID, sharingGroupUUID: sharingGroupUUID)
        
        let key = FileIndexRepository.LookupKey.primaryKeys(sharingGroupUUID: sharingGroupUUID, fileUUID: uploadResult.request.fileUUID)
        
        let fileIndexResult = FileIndexRepository(db).lookup(key: key, modelInit: FileIndex.init)
        guard case .found(let obj) = fileIndexResult,
            let fileIndexObj = obj as? FileIndex else {
            XCTFail()
            return
        }
        
        guard fileIndexObj.lastUploadedCheckSum != nil else {
            XCTFail()
            return
        }
        
        self.getIndex(expectedFiles: [uploadResult.request], masterVersionExpected: 1, sharingGroupUUID: sharingGroupUUID)
        
        guard let (files, sharingGroups) = getIndex(sharingGroupUUID: sharingGroupUUID),
            let theFiles = files else {
            XCTFail()
            return
        }
        
        XCTAssert(files != nil)
        
        guard sharingGroups.count == 1, sharingGroups[0].sharingGroupUUID == sharingGroupUUID,  sharingGroups[0].sharingGroupName == nil,
            sharingGroups[0].deleted == false
            else {
            XCTFail()
            return
        }
        
        for file in theFiles {
            guard let cloudStorageType = file.cloudStorageType else {
                XCTFail()
                return
            }
            
            if file.fileUUID == uploadResult.request.fileUUID {
                XCTAssert(testAccount.scheme.cloudStorageType == cloudStorageType)
            }
        }
    }
    
    func testIndexWithTwoFiles() {
        let deviceUUID = Foundation.UUID().uuidString
        guard let uploadResult1 = uploadTextFile(deviceUUID:deviceUUID),
            let sharingGroupUUID = uploadResult1.sharingGroupUUID else {
            XCTFail()
            return
        }
        
        guard let uploadResult2 = uploadJPEGFile(deviceUUID:deviceUUID, addUser:.no(sharingGroupUUID: sharingGroupUUID)) else {
            XCTFail()
            return
        }
        
        // Have to do a DoneUploads to transfer the files into the FileIndex
        self.sendDoneUploads(expectedNumberOfUploads: 2, deviceUUID:deviceUUID, sharingGroupUUID: sharingGroupUUID)
        
        self.getIndex(expectedFiles: [uploadResult1.request, uploadResult2.request],masterVersionExpected: 1, sharingGroupUUID: sharingGroupUUID)
    }
        
    func testDownloadFileTextSucceeds() {
        downloadTextFile(masterVersionExpectedWithDownload: 1)
    }
    
    func testDownloadURLFileSucceeds() {
        downloadServerFile(mimeType: .url, file: .testUrlFile, masterVersionExpectedWithDownload: 1)
    }
    
    func testDownloadFileTextWithASimulatedUserChangeSucceeds() {
        let testAccount:TestAccount = .primaryOwningAccount
        let deviceUUID = Foundation.UUID().uuidString
        
        guard let uploadResult = uploadTextFile(testAccount: testAccount, deviceUUID: deviceUUID),
            let sharingGroupUUID = uploadResult.sharingGroupUUID else {
            XCTFail()
            return
        }
        
        self.sendDoneUploads(testAccount: testAccount, expectedNumberOfUploads: 1, deviceUUID:deviceUUID, sharingGroupUUID: sharingGroupUUID)
        
        var cloudStorageCreds: CloudStorage!
        
        let exp = expectation(description: "\(#function)\(#line)")
        testAccount.scheme.doHandler(for: .getCredentials, testAccount: testAccount) { creds in
            // For social accounts, e.g., Facebook, this will result in nil and fail below. That's what we want. Just trying to get cloud storage creds.
            cloudStorageCreds = creds as? CloudStorage
            
            exp.fulfill()
        }
        waitForExpectations(timeout: 10, handler: nil)
        
        guard cloudStorageCreds != nil else {
            XCTFail()
            return
        }
        
        let file = TestFile.test2
        
        let checkSum = file.checkSum(type: testAccount.scheme.accountName)

        let uploadRequest = UploadFileRequest()
        uploadRequest.fileUUID = uploadResult.request.fileUUID
        uploadRequest.mimeType = "text/plain"
        uploadRequest.fileVersion = 0
        uploadRequest.masterVersion = 1
        uploadRequest.sharingGroupUUID = sharingGroupUUID
        uploadRequest.checkSum = checkSum
    
        let options = CloudStorageFileNameOptions(cloudFolderName: ServerTestCase.cloudFolderName, mimeType: "text/plain")

        let cloudFileName = uploadRequest.cloudFileName(deviceUUID:deviceUUID, mimeType: uploadRequest.mimeType)
        deleteFile(testAccount: testAccount, cloudFileName: cloudFileName, options: options)

        uploadFile(accountType: testAccount.scheme.accountName, creds: cloudStorageCreds, deviceUUID: deviceUUID, testFile: file, uploadRequest: uploadRequest, options: options)
        
        // Don't want the download to fail just due to a checksum mismatch.
        uploadResult.request.checkSum = checkSum

        downloadTextFile(testAccount: testAccount, masterVersionExpectedWithDownload: 1, uploadFileRequest: uploadResult.request, contentsChangedExpected: true)
    }
    
    func testDownloadTextFileWhereFileDeletedGivesGoneResponse() {
        let testAccount:TestAccount = .primaryOwningAccount
        let deviceUUID = Foundation.UUID().uuidString
        
        guard let uploadResult = uploadTextFile(testAccount: testAccount, deviceUUID: deviceUUID),
            let sharingGroupUUID = uploadResult.sharingGroupUUID else {
            XCTFail()
            return
        }
        
        self.sendDoneUploads(testAccount: testAccount, expectedNumberOfUploads: 1, deviceUUID:deviceUUID, sharingGroupUUID: sharingGroupUUID)
        
        var checkSum:String!
        let file = TestFile.test2
        
        checkSum = file.checkSum(type: testAccount.scheme.accountName)

        let uploadRequest = UploadFileRequest()
        uploadRequest.fileUUID = uploadResult.request.fileUUID
        uploadRequest.mimeType = "text/plain"
        uploadRequest.fileVersion = 0
        uploadRequest.masterVersion = 1
        uploadRequest.sharingGroupUUID = sharingGroupUUID
        uploadRequest.checkSum = checkSum
    
        let options = CloudStorageFileNameOptions(cloudFolderName: ServerTestCase.cloudFolderName, mimeType: "text/plain")

        let cloudFileName = uploadRequest.cloudFileName(deviceUUID:deviceUUID, mimeType: uploadRequest.mimeType)
        deleteFile(testAccount: testAccount, cloudFileName: cloudFileName, options: options)

        self.performServerTest(testAccount:testAccount) { expectation, testCreds in
            let headers = self.setupHeaders(testUser:testAccount, accessToken: testCreds.accessToken, deviceUUID:deviceUUID)
            
            let downloadFileRequest = DownloadFileRequest()
            downloadFileRequest.fileUUID = uploadRequest.fileUUID
            downloadFileRequest.masterVersion = 1
            downloadFileRequest.fileVersion = 0
            downloadFileRequest.sharingGroupUUID = sharingGroupUUID
            
            self.performRequest(route: ServerEndpoints.downloadFile, responseDictFrom:.header, headers: headers, urlParameters: "?" + downloadFileRequest.urlParameters()!, body:nil) { response, dict in
                Log.info("Status code: \(response!.statusCode)")
                
                if let dict = dict,
                    let downloadFileResponse = try? DownloadFileResponse.decode(dict) {
                    XCTAssert(downloadFileResponse.gone == GoneReason.fileRemovedOrRenamed.rawValue)
                }
                else {
                    XCTFail()
                }
                
                expectation.fulfill()
            }
        }
    }
    
    func testDownloadFileTextWhereMasterVersionDiffersFails() {
        downloadTextFile(masterVersionExpectedWithDownload: 0, expectUpdatedMasterUpdate:true)
    }
    
    func testDownloadFileTextWithAppMetaDataSucceeds() {
        downloadTextFile(masterVersionExpectedWithDownload: 1,
            appMetaData:AppMetaData(version: 0, contents: "{ \"foo\": \"bar\" }"))
    }
    
    func testDownloadFileTextWithDifferentDownloadVersion() {
        downloadTextFile(masterVersionExpectedWithDownload: 1, downloadFileVersion:1, expectedError: true)
    }
    
    func testIndexWithFakeSharingGroupUUIDFails() {
        let deviceUUID = Foundation.UUID().uuidString
        guard let uploadResult = uploadTextFile(deviceUUID:deviceUUID), let sharingGroupUUID = uploadResult.sharingGroupUUID else {
            XCTFail()
            return
        }
        
        // Have to do a DoneUploads to transfer the files into the FileIndex
        self.sendDoneUploads(expectedNumberOfUploads: 1, deviceUUID:deviceUUID, sharingGroupUUID: sharingGroupUUID)
        
        let invalidSharingGroupUUID = UUID().uuidString
        
        self.getIndex(expectedFiles: [uploadResult.request], masterVersionExpected: 1, sharingGroupUUID: invalidSharingGroupUUID, errorExpected: true)
    }
    
    func testIndexWithBadSharingGroupUUIDFails() {
        let deviceUUID = Foundation.UUID().uuidString
        guard let uploadResult = uploadTextFile(deviceUUID:deviceUUID),
            let sharingGroupUUID = uploadResult.sharingGroupUUID else {
            XCTFail()
            return
        }
        
        // Have to do a DoneUploads to transfer the files into the FileIndex
        self.sendDoneUploads(expectedNumberOfUploads: 1, deviceUUID:deviceUUID, sharingGroupUUID: sharingGroupUUID)
        
        let workingButBadSharingGroupUUID = UUID().uuidString
        guard addSharingGroup(sharingGroupUUID: workingButBadSharingGroupUUID) else {
            XCTFail()
            return
        }
        
        self.getIndex(expectedFiles: [uploadResult.request], masterVersionExpected: 1, sharingGroupUUID: workingButBadSharingGroupUUID, errorExpected: true)
    }
    
    // TODO: *0*: Make sure we're not trying to download a file that has already been deleted.
    
    // TODO: *1* Make sure its an error for a different user to download our file even if they have the fileUUID and fileVersion.
    
    // TODO: *1* Test that two concurrent downloads work.
}

extension FileControllerTests {
    static var allTests : [(String, (FileControllerTests) -> () throws -> Void)] {
        return [
            ("testMasterVersionConflict1", testMasterVersionConflict1),
            ("testMasterVersionConflict2", testMasterVersionConflict2),
            ("testIndexWithNoFiles", testIndexWithNoFiles),
            ("testGetIndexForOnlySharingGroupsWorks", testGetIndexForOnlySharingGroupsWorks),
            ("testIndexWithOneFile", testIndexWithOneFile),
            ("testIndexWithTwoFiles", testIndexWithTwoFiles),
            ("testDownloadFileTextSucceeds", testDownloadFileTextSucceeds),
            ("testDownloadURLFileSucceeds", testDownloadURLFileSucceeds),
            ("testDownloadFileTextWithASimulatedUserChangeSucceeds", testDownloadFileTextWithASimulatedUserChangeSucceeds),
            ("testDownloadTextFileWhereFileDeletedGivesGoneResponse",
                testDownloadTextFileWhereFileDeletedGivesGoneResponse),
            ("testDownloadFileTextWhereMasterVersionDiffersFails", testDownloadFileTextWhereMasterVersionDiffersFails),
            ("testDownloadFileTextWithAppMetaDataSucceeds", testDownloadFileTextWithAppMetaDataSucceeds),
            ("testDownloadFileTextWithDifferentDownloadVersion", testDownloadFileTextWithDifferentDownloadVersion),
            ("testIndexWithFakeSharingGroupUUIDFails", testIndexWithFakeSharingGroupUUIDFails),
            ("testIndexWithBadSharingGroupUUIDFails", testIndexWithBadSharingGroupUUIDFails)
        ]
    }
    
    func testLinuxTestSuiteIncludesAllTests() {
        linuxTestSuiteIncludesAllTests(testType:FileControllerTests.self)
    }
}


