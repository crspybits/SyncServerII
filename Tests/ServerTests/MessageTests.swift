//
//  MessageTests.swift
//  Server
//
//  Created by Christopher Prince on 1/15/17.
//
//

import XCTest
@testable import Server
import Foundation
import SyncServerShared

class MessageTests: ServerTestCase, LinuxTestable {

    override func setUp() {
         super.setUp()
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }
    
    override func tearDown() {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
         super.tearDown()
    }
    
    func testIntConversions() {
        let uuidString1 = Foundation.UUID().uuidString

        let uploadRequest = UploadFileRequest()
        uploadRequest.fileUUID = uuidString1
        uploadRequest.mimeType = "text/plain"
        uploadRequest.fileVersion = FileVersionInt(1)
        uploadRequest.masterVersion = MasterVersionInt(42)
        uploadRequest.sharingGroupUUID = UUID().uuidString
        uploadRequest.checkSum = TestFile.test1.dropboxCheckSum
        
        guard uploadRequest.valid() else {
            XCTFail()
            return
        }
        
        XCTAssert(uploadRequest.fileVersion == 1)        
        XCTAssert(uploadRequest.masterVersion == 42)
  }

    func testURLParameters() {
        let uuidString1 = Foundation.UUID().uuidString
        let sharingGroupUUID = UUID().uuidString
        
        let uploadRequest = UploadFileRequest()
        uploadRequest.checkSum = TestFile.test1.dropboxCheckSum
        uploadRequest.fileUUID = uuidString1
        uploadRequest.fileVersion = FileVersionInt(1)
        uploadRequest.masterVersion = MasterVersionInt(42)
        uploadRequest.mimeType = "text/plain"
        uploadRequest.sharingGroupUUID = sharingGroupUUID

        guard let result = uploadRequest.urlParameters() else {
            XCTFail()
            return
        }
        
        let resultArray = result.components(separatedBy: "&")
        
        let expectedCheckSum = "checkSum=\(TestFile.test1.dropboxCheckSum)"
        let expectedFileUUID = "fileUUID=\(uuidString1)"
        let expectedFileVersion = "fileVersion=1"
        let expectedMasterVersion = "masterVersion=42"
        let expectedMimeType = "mimeType=text%2Fplain"
        let expectedSharingGroupUUID = "sharingGroupUUID=\(sharingGroupUUID)"

        XCTAssert(resultArray[0] == expectedCheckSum)
        XCTAssert(resultArray[1] == expectedFileUUID)
        XCTAssert(resultArray[2] == expectedFileVersion)
        XCTAssert(resultArray[3] == expectedMasterVersion)
        XCTAssert(resultArray[4] == expectedMimeType)
        XCTAssert(resultArray[5] == expectedSharingGroupUUID)

        let expected =
            expectedCheckSum + "&" +
            expectedFileUUID + "&" +
            expectedFileVersion + "&" +
            expectedMasterVersion + "&" +
            expectedMimeType + "&" +
            expectedSharingGroupUUID

        XCTAssert(result == expected, "Result was: \(String(describing: result))")
    }
    
    func testURLParametersForUploadDeletion() {
        let uuidString = Foundation.UUID().uuidString

        let sharingGroupUUID = UUID().uuidString
        
        let uploadDeletionRequest = UploadDeletionRequest()
        uploadDeletionRequest.fileUUID = uuidString
        uploadDeletionRequest.fileVersion = FileVersionInt(99)
        uploadDeletionRequest.masterVersion = MasterVersionInt(23)
        uploadDeletionRequest.actualDeletion = true
        uploadDeletionRequest.sharingGroupUUID = sharingGroupUUID
        
        let result = uploadDeletionRequest.urlParameters()
        
        let expectedURLParams =
            "actualDeletion=true&" +
            "fileUUID=\(uuidString)&" +
            "fileVersion=99&" +
            "masterVersion=23&" +
            "sharingGroupUUID=\(sharingGroupUUID)"
        
        XCTAssert(result == expectedURLParams, "Result was: \(String(describing: expectedURLParams))")
    }
    
    func testBadUUIDForFileName() {
        let sharingGroupUUID = UUID().uuidString
        let uploadRequest = UploadFileRequest()
        uploadRequest.fileUUID = "foobar"
        uploadRequest.mimeType = "text/plain"
        uploadRequest.fileVersion = FileVersionInt(1)
        uploadRequest.masterVersion = MasterVersionInt(42)
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
        uploadRequest.fileVersion = FileVersionInt(1)
        uploadRequest.masterVersion = MasterVersionInt(42)
        uploadRequest.sharingGroupUUID = sharingGroupUUID
        uploadRequest.checkSum = TestFile.test1.dropboxCheckSum
        
        guard uploadRequest.valid() else {
            XCTFail()
            return
        }
        
        XCTAssert(uploadRequest.fileUUID == uuidString1)
        XCTAssert(uploadRequest.mimeType == "text/plain")
        XCTAssert(uploadRequest.fileVersion == FileVersionInt(1))
        XCTAssert(uploadRequest.masterVersion == MasterVersionInt(42))
        XCTAssert(uploadRequest.sharingGroupUUID == sharingGroupUUID)
        XCTAssert(uploadRequest.checkSum == TestFile.test1.dropboxCheckSum)
    }
    
    func testNonNilRequestMessageParams() {
        let upload = RedeemSharingInvitationRequest()
        upload.sharingInvitationUUID = "foobar"
        XCTAssert(upload.valid())
        XCTAssert(upload.sharingInvitationUUID == "foobar")
    }
    
    // Because of some Linux problems I was having.
    func testDoneUploadsResponse() {
        let numberUploads = Int32(23)
        let response = DoneUploadsResponse()
        response.numberUploadsTransferred = numberUploads
        XCTAssert(response.numberUploadsTransferred == numberUploads)
        
        guard let jsonDict = response.toDictionary else {
            XCTFail()
            return
        }
        
        // Could not cast value of type 'Foundation.NSNumber' (0x7fd77dcf8188) to 'Swift.Int32' (0x7fd77e0c9b18).
        guard let response2 = try? DoneUploadsResponse.decode(jsonDict) else {
            XCTFail()
            return
        }
        
        XCTAssert(response2.numberUploadsTransferred == numberUploads)
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

extension MessageTests {
    static var allTests : [(String, (MessageTests) -> () throws -> Void)] {
        return [
            ("testIntConversions", testIntConversions),
            ("testURLParameters", testURLParameters),
            ("testURLParametersForUploadDeletion", testURLParametersForUploadDeletion),
            ("testBadUUIDForFileName", testBadUUIDForFileName),
            ("testPropertyHasValue", testPropertyHasValue),
            ("testNonNilRequestMessageParams", testNonNilRequestMessageParams),
            ("testDoneUploadsResponse", testDoneUploadsResponse),
            ("testValidGetSharingInvitationInfoRequest", testValidGetSharingInvitationInfoRequest),
            ("testInvalidGetSharingInvitationInfoRequest", testInvalidGetSharingInvitationInfoRequest)
        ]
    }

    func testLinuxTestSuiteIncludesAllTests() {
        linuxTestSuiteIncludesAllTests(testType:MessageTests.self)
    }
}

