//
//  MessageTests.swift
//  Server
//
//  Created by Christopher Prince on 1/15/17.
//
//

import XCTest
@testable import Server
@testable import TestsCommon
import Foundation
import ServerShared

class MessageTests: ServerTestCase {

    override func setUp() {
         super.setUp()
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }
    
    override func tearDown() {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
         super.tearDown()
    }
    
    func testIfUploadFileRequestIsValid() {
        let uuidString1 = Foundation.UUID().uuidString

        let uploadRequest = UploadFileRequest()
        uploadRequest.fileUUID = uuidString1
        uploadRequest.mimeType = "text/plain"
        uploadRequest.sharingGroupUUID = UUID().uuidString
        uploadRequest.checkSum = TestFile.test1.dropboxCheckSum
        uploadRequest.uploadCount = 1
        uploadRequest.uploadIndex = 1
        
        guard uploadRequest.valid() else {
            XCTFail()
            return
        }
  }

    func testURLParameters() {
        let uuidString1 = Foundation.UUID().uuidString
        let sharingGroupUUID = UUID().uuidString
        
        let uploadRequest = UploadFileRequest()
        uploadRequest.checkSum = TestFile.test1.dropboxCheckSum
        uploadRequest.fileUUID = uuidString1
        uploadRequest.mimeType = "text/plain"
        uploadRequest.sharingGroupUUID = sharingGroupUUID

        guard let result = uploadRequest.urlParameters() else {
            XCTFail()
            return
        }
        
        let resultArray = result.components(separatedBy: "&")
        
        let expectedCheckSum = "checkSum=\(TestFile.test1.dropboxCheckSum!)"
        let expectedFileUUID = "fileUUID=\(uuidString1)"
        let expectedMimeType = "mimeType=text%2Fplain"
        let expectedSharingGroupUUID = "sharingGroupUUID=\(sharingGroupUUID)"

        guard resultArray.count == 4 else {
            XCTFail("result: \(result); resultArray: \(resultArray)")
            return
        }
        
        XCTAssert(resultArray[0] == expectedCheckSum)
        XCTAssert(resultArray[1] == expectedFileUUID)
        XCTAssert(resultArray[2] == expectedMimeType)
        XCTAssert(resultArray[3] == expectedSharingGroupUUID)

        let expected =
            expectedCheckSum + "&" +
            expectedFileUUID + "&" +
            expectedMimeType + "&" +
            expectedSharingGroupUUID

        XCTAssert(result == expected, "Result was: \(String(describing: result)); Expected was: \(String(describing: expected))")
    }
    
    func testURLParametersForUploadDeletion() {
        let uuidString = Foundation.UUID().uuidString

        let sharingGroupUUID = UUID().uuidString
        
        let uploadDeletionRequest = UploadDeletionRequest()
        uploadDeletionRequest.fileUUID = uuidString
        uploadDeletionRequest.sharingGroupUUID = sharingGroupUUID
        
        let result = uploadDeletionRequest.urlParameters()

        let expectedURLParams =
            "fileUUID=\(uuidString)&" +
            "sharingGroupUUID=\(sharingGroupUUID)"
        
        XCTAssert(result == expectedURLParams, "Expected: \(String(describing: expectedURLParams)); actual: \(String(describing: result))")
    }
    
    func testBadUUIDForFileName() {
        let sharingGroupUUID = UUID().uuidString
        let uploadRequest = UploadFileRequest()
        uploadRequest.fileUUID = "foobar"
        uploadRequest.mimeType = "text/plain"
        uploadRequest.sharingGroupUUID = sharingGroupUUID
        uploadRequest.checkSum = TestFile.test1.dropboxCheckSum
        
        XCTAssert(!uploadRequest.valid())
    }
    
    func testPropertyHasValue() {
        let uuidString1 = Foundation.UUID().uuidString
        let sharingGroupUUID = UUID().uuidString

        let uploadRequest = UploadFileRequest()
        uploadRequest.fileUUID = uuidString1
        uploadRequest.mimeType = "text/plain"
        uploadRequest.sharingGroupUUID = sharingGroupUUID
        uploadRequest.checkSum = TestFile.test1.dropboxCheckSum
        uploadRequest.uploadCount = 1
        uploadRequest.uploadIndex = 1
        
        guard uploadRequest.valid() else {
            XCTFail()
            return
        }
        
        XCTAssert(uploadRequest.fileUUID == uuidString1)
        XCTAssert(uploadRequest.mimeType == "text/plain")
        XCTAssert(uploadRequest.sharingGroupUUID == sharingGroupUUID)
        XCTAssert(uploadRequest.checkSum == TestFile.test1.dropboxCheckSum)
    }
    
    func testNonNilRequestMessageParams() {
        let upload = RedeemSharingInvitationRequest()
        upload.sharingInvitationUUID = "foobar"
        XCTAssert(upload.valid())
        XCTAssert(upload.sharingInvitationUUID == "foobar")
    }
    
    func testValidGetSharingInvitationInfoRequest() {
        let request = GetSharingInvitationInfoRequest()
        request.sharingInvitationUUID = Foundation.UUID().uuidString
        XCTAssert(request.valid())
    }
    
    func testInvalidGetSharingInvitationInfoRequest() {
        let request = GetSharingInvitationInfoRequest()
        request.sharingInvitationUUID = "foobar"
        XCTAssert(!request.valid())
    }
}

