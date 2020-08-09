//
//  FileController_DownloadTests.swift
//  FileControllerTests
//
//  Created by Christopher G Prince on 8/8/20.
//

import XCTest
@testable import Server
@testable import TestsCommon
import LoggerAPI
import Foundation
import ServerShared
import HeliumLogger
import ServerAccount

class FileController_DownloadTests: ServerTestCase {
    func testDownloadFileTextSucceeds() {
        let file:TestFile = .test1
        
        guard let result = downloadTextFile(file: file) else {
            XCTFail()
            return
        }
        
        guard let data = result.data else {
            XCTFail()
            return
        }
        
        guard let downloadedString = String(data: data, encoding: .utf8) else {
            XCTFail()
            return
        }
        
        guard case .string(let fileString) = file.contents else {
            XCTFail()
            return
        }
        
        XCTAssert(fileString == downloadedString)
    }
    
    func testDownloadURLFileSucceeds() {
        downloadServerFile(mimeType: .url, file: .testUrlFile)
    }
    
    func testDownloadFileTextWithASimulatedUserChangeSucceeds() {
        let testAccount:TestAccount = .primaryOwningAccount
        let deviceUUID = Foundation.UUID().uuidString
        
        guard let uploadResult = uploadTextFile(testAccount: testAccount, deviceUUID: deviceUUID),
            let sharingGroupUUID = uploadResult.sharingGroupUUID else {
            XCTFail()
            return
        }
        
        //self.sendDoneUploads(testAccount: testAccount, expectedNumberOfUploads: 1, deviceUUID:deviceUUID, sharingGroupUUID: sharingGroupUUID)
        
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
        uploadRequest.sharingGroupUUID = sharingGroupUUID
        uploadRequest.checkSum = checkSum
    
        let options = CloudStorageFileNameOptions(cloudFolderName: ServerTestCase.cloudFolderName, mimeType: "text/plain")

        // DEPRECATED
        var cloudFileName: String! // = uploadRequest.cloudFileName(deviceUUID:deviceUUID, mimeType: uploadRequest.mimeType)
        deleteFile(testAccount: testAccount, cloudFileName: cloudFileName, options: options)

        uploadFile(accountType: testAccount.scheme.accountName, creds: cloudStorageCreds, deviceUUID: deviceUUID, testFile: file, uploadRequest: uploadRequest, fileVersion: 0, options: options)
        
        // Don't want the download to fail just due to a checksum mismatch.
        uploadResult.request.checkSum = checkSum

        downloadTextFile(testAccount: testAccount, uploadFileRequest: uploadResult.request, contentsChangedExpected: true)
    }
    
    func testDownloadTextFileWhereFileDeletedGivesGoneResponse() {
        let testAccount:TestAccount = .primaryOwningAccount
        let deviceUUID = Foundation.UUID().uuidString
        
        guard let uploadResult = uploadTextFile(testAccount: testAccount, deviceUUID: deviceUUID),
            let sharingGroupUUID = uploadResult.sharingGroupUUID else {
            XCTFail()
            return
        }
        
        //self.sendDoneUploads(testAccount: testAccount, expectedNumberOfUploads: 1, deviceUUID:deviceUUID, sharingGroupUUID: sharingGroupUUID)
        
        var checkSum:String!
        let file = TestFile.test2
        
        checkSum = file.checkSum(type: testAccount.scheme.accountName)

        let uploadRequest = UploadFileRequest()
        uploadRequest.fileUUID = uploadResult.request.fileUUID
        uploadRequest.mimeType = "text/plain"
        uploadRequest.sharingGroupUUID = sharingGroupUUID
        uploadRequest.checkSum = checkSum
    
        let options = CloudStorageFileNameOptions(cloudFolderName: ServerTestCase.cloudFolderName, mimeType: "text/plain")

        // DEPRECATED
        var cloudFileName: String! // = uploadRequest.cloudFileName(deviceUUID:deviceUUID, mimeType: uploadRequest.mimeType)
        deleteFile(testAccount: testAccount, cloudFileName: cloudFileName, options: options)

        self.performServerTest(testAccount:testAccount) { expectation, testCreds in
            let headers = self.setupHeaders(testUser:testAccount, accessToken: testCreds.accessToken, deviceUUID:deviceUUID)
            
            let downloadFileRequest = DownloadFileRequest()
            downloadFileRequest.fileUUID = uploadRequest.fileUUID
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
    
    func testDownloadFileTextWithAppMetaDataSucceeds() {
        downloadTextFile(appMetaData:"{ \"foo\": \"bar\" }")
    }
    
    func testDownloadFileTextWithDifferentDownloadVersion() {
        downloadTextFile(downloadFileVersion:1, expectedError: true)
    }
}
