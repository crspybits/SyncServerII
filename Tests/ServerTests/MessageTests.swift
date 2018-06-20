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

        guard let uploadRequest = UploadFileRequest(json: [
            UploadFileRequest.fileUUIDKey : uuidString1,
            UploadFileRequest.mimeTypeKey: "text/plain",
            UploadFileRequest.fileVersionKey: FileVersionInt(1),
            UploadFileRequest.masterVersionKey: MasterVersionInt(42)
        ]) else {
            XCTFail()
            return
        }
        
        XCTAssert(uploadRequest.fileVersion == 1)        
        XCTAssert(uploadRequest.masterVersion == 42)
  }

    func testURLParameters() {
        let uuidString1 = Foundation.UUID().uuidString
        
        let uploadRequest = UploadFileRequest(json: [
            UploadFileRequest.fileUUIDKey : uuidString1,
            UploadFileRequest.mimeTypeKey: "text/plain",
            UploadFileRequest.fileVersionKey: FileVersionInt(1),
            UploadFileRequest.masterVersionKey: MasterVersionInt(42)
        ])
        
        let result = uploadRequest!.urlParameters()
        
        XCTAssert(result == "\(UploadFileRequest.fileUUIDKey)=\(uuidString1)&mimeType=text%2Fplain&\(UploadFileRequest.fileVersionKey)=1&\(UploadFileRequest.masterVersionKey)=42", "Result was: \(String(describing: result))")
    }
    
    func testURLParametersWithIntegersAsStrings() {
        let uuidString1 = Foundation.UUID().uuidString

        let uploadRequest = UploadFileRequest(json: [
            UploadFileRequest.fileUUIDKey : uuidString1,
            UploadFileRequest.mimeTypeKey: "text/plain",
            UploadFileRequest.fileVersionKey: "1",
            UploadFileRequest.masterVersionKey: "42"
        ])
        
        let result = uploadRequest!.urlParameters()
        
        XCTAssert(result == "\(UploadFileRequest.fileUUIDKey)=\(uuidString1)&mimeType=text%2Fplain&\(UploadFileRequest.fileVersionKey)=1&\(UploadFileRequest.masterVersionKey)=42", "Result was: \(String(describing: result))")
    }
    
    func testURLParametersForUploadDeletion() {
        let uuidString = Foundation.UUID().uuidString

        let uploadDeletionRequest = UploadDeletionRequest(json: [
            UploadDeletionRequest.fileUUIDKey: uuidString,
            UploadDeletionRequest.fileVersionKey: FileVersionInt(99),
            UploadDeletionRequest.masterVersionKey: MasterVersionInt(23),
            UploadDeletionRequest.actualDeletionKey: Int32(1)
        ])
        
        let result = uploadDeletionRequest!.urlParameters()
        
        let expectedURLParams =
            "\(UploadDeletionRequest.fileUUIDKey)=\(uuidString)&" +
            "\(UploadDeletionRequest.fileVersionKey)=99&" +
            "\(UploadDeletionRequest.masterVersionKey)=23&" +
            "\(UploadDeletionRequest.actualDeletionKey)=1"
        
        XCTAssert(result == expectedURLParams, "Result was: \(String(describing: result))")
    }
    
    func testBadUUIDForFileName() {
        let uploadRequest = UploadFileRequest(json: [
            UploadFileRequest.fileUUIDKey : "foobar",
            UploadFileRequest.mimeTypeKey: "text/plain",
            UploadFileRequest.fileVersionKey: FileVersionInt(1),
            UploadFileRequest.masterVersionKey: MasterVersionInt(42)
        ])
        XCTAssert(uploadRequest == nil)
    }
    
    func testPropertyHasValue() {
        let uuidString1 = Foundation.UUID().uuidString

        guard let uploadRequest = UploadFileRequest(json: [
            UploadFileRequest.fileUUIDKey : uuidString1,
            UploadFileRequest.mimeTypeKey: "text/plain",
            UploadFileRequest.fileVersionKey: FileVersionInt(1),
            UploadFileRequest.masterVersionKey: MasterVersionInt(42)
        ]) else {
            XCTFail()
            return
        }
        
        XCTAssert(uploadRequest.fileUUID == uuidString1)
        XCTAssert(uploadRequest.mimeType == "text/plain")
        XCTAssert(uploadRequest.fileVersion == FileVersionInt(1))
        XCTAssert(uploadRequest.masterVersion == MasterVersionInt(42))
    }
    
    func testNilRequestMessageParams() {
        let upload = RedeemSharingInvitationRequest(json: [:])
        XCTAssert(upload == nil)
    }
    
    func testNonNilRequestMessageParams() {
        let upload = RedeemSharingInvitationRequest(json: [
            RedeemSharingInvitationRequest.sharingInvitationUUIDKey:"foobar"])
        XCTAssert(upload != nil)
        XCTAssert(upload!.sharingInvitationUUID == "foobar")
    }
    
    // Because of some Linux problems I was having.
    func testDoneUploadsResponse() {
        let numberUploads = Int32(23)
        let response = DoneUploadsResponse(json:[
            DoneUploadsResponse.numberUploadsTransferredKey: numberUploads
        ])!
        XCTAssert(response.numberUploadsTransferred == numberUploads)
        
        guard let jsonDict = response.toJSON() else {
            XCTFail()
            return
        }
        
        // Could not cast value of type 'Foundation.NSNumber' (0x7fd77dcf8188) to 'Swift.Int32' (0x7fd77e0c9b18).
        XCTAssert(jsonDict[DoneUploadsResponse.numberUploadsTransferredKey] as! Int32 == numberUploads)
    }
}

extension MessageTests {
    static var allTests : [(String, (MessageTests) -> () throws -> Void)] {
        return [
            ("testIntConversions", testIntConversions),
            ("testURLParameters", testURLParameters),
            ("testURLParametersWithIntegersAsStrings", testURLParametersWithIntegersAsStrings),
            ("testURLParametersForUploadDeletion", testURLParametersForUploadDeletion),
            ("testBadUUIDForFileName", testBadUUIDForFileName),
            ("testPropertyHasValue", testPropertyHasValue),
            ("testNilRequestMessageParams", testNilRequestMessageParams),
            ("testNonNilRequestMessageParams", testNonNilRequestMessageParams),
            ("testDoneUploadsResponse", testDoneUploadsResponse)
        ]
    }

    func testLinuxTestSuiteIncludesAllTests() {
        linuxTestSuiteIncludesAllTests(testType:MessageTests.self)
    }
}

