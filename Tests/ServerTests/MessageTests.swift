//
//  MessageTests.swift
//  Server
//
//  Created by Christopher Prince on 1/15/17.
//
//

import XCTest
@testable import Server
import PerfectLib
import Foundation
import SyncServerShared

class MessageTests: ServerTestCase {

    override func setUp() {
        super.setUp()
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }
    
    override func tearDown() {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
        super.tearDown()
    }
    
    func testIntConversions() {
        let uuidString1 = PerfectLib.UUID().string

        let uploadRequest = UploadFileRequest(json: [
            UploadFileRequest.fileUUIDKey : uuidString1,
            UploadFileRequest.mimeTypeKey: "text/plain",
            UploadFileRequest.cloudFolderNameKey: "CloudFolder",
            UploadFileRequest.fileVersionKey: FileVersionInt(1),
            UploadFileRequest.masterVersionKey: MasterVersionInt(42),
            UploadFileRequest.creationDateKey: DateExtras.date(Date(), toFormat: .DATETIME),
            UploadFileRequest.updateDateKey: DateExtras.date(Date(), toFormat: .DATETIME)
        ])
        
        let fileVersion = valueFor(property: UploadFileRequest.fileVersionKey, of: uploadRequest! as Any) as? FileVersionInt
        XCTAssert(fileVersion == 1, "fileVersion = \(String(describing: fileVersion))")
        
        let masterVersion = valueFor(property: UploadFileRequest.masterVersionKey, of: uploadRequest!  as Any) as? MasterVersionInt
        XCTAssert(masterVersion == 42, "masterVersion = \(String(describing: masterVersion))")
  }

    func testURLParameters() {
        let uuidString1 = PerfectLib.UUID().string
        let dateString = DateExtras.date(Date(), toFormat: .DATETIME)
        let escapedDateString = dateString.escape()!
        
        let uploadRequest = UploadFileRequest(json: [
            UploadFileRequest.fileUUIDKey : uuidString1,
            UploadFileRequest.mimeTypeKey: "text/plain",
            UploadFileRequest.cloudFolderNameKey: "CloudFolder",
            UploadFileRequest.fileVersionKey: FileVersionInt(1),
            UploadFileRequest.masterVersionKey: MasterVersionInt(42),
            UploadFileRequest.creationDateKey: dateString,
            UploadFileRequest.updateDateKey: dateString
        ])
        
        let result = uploadRequest!.urlParameters()
        
        XCTAssert(result == "\(UploadFileRequest.fileUUIDKey)=\(uuidString1)&mimeType=text%2Fplain&\(UploadFileRequest.cloudFolderNameKey)=CloudFolder&\(UploadFileRequest.fileVersionKey)=1&\(UploadFileRequest.masterVersionKey)=42&\(UploadFileRequest.creationDateKey)=\(escapedDateString)&\(UploadFileRequest.updateDateKey)=\(escapedDateString)", "Result was: \(String(describing: result))")
    }
    
    func testURLParametersWithIntegersAsStrings() {
        let uuidString1 = PerfectLib.UUID().string
        let dateString = DateExtras.date(Date(), toFormat: .DATETIME)
        let escapedDateString = dateString.escape()!

        let uploadRequest = UploadFileRequest(json: [
            UploadFileRequest.fileUUIDKey : uuidString1,
            UploadFileRequest.mimeTypeKey: "text/plain",
            UploadFileRequest.cloudFolderNameKey: "CloudFolder",
            UploadFileRequest.fileVersionKey: "1",
            UploadFileRequest.masterVersionKey: "42",
            UploadFileRequest.creationDateKey: dateString,
            UploadFileRequest.updateDateKey: dateString
        ])
        
        let result = uploadRequest!.urlParameters()
        
        XCTAssert(result == "\(UploadFileRequest.fileUUIDKey)=\(uuidString1)&mimeType=text%2Fplain&\(UploadFileRequest.cloudFolderNameKey)=CloudFolder&\(UploadFileRequest.fileVersionKey)=1&\(UploadFileRequest.masterVersionKey)=42&\(UploadFileRequest.creationDateKey)=\(escapedDateString)&\(UploadFileRequest.updateDateKey)=\(escapedDateString)", "Result was: \(String(describing: result))")
    }
    
    func testURLParametersForUploadDeletion() {
        let uuidString = PerfectLib.UUID().string

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
        let dateString = DateExtras.date(Date(), toFormat: .DATETIME)

        let uploadRequest = UploadFileRequest(json: [
            UploadFileRequest.fileUUIDKey : "foobar",
            UploadFileRequest.mimeTypeKey: "text/plain",
            UploadFileRequest.cloudFolderNameKey: "CloudFolder",
            UploadFileRequest.fileVersionKey: FileVersionInt(1),
            UploadFileRequest.masterVersionKey: MasterVersionInt(42),
            UploadFileRequest.creationDateKey: dateString,
            UploadFileRequest.updateDateKey: dateString
        ])
        XCTAssert(uploadRequest == nil)
    }
    
    func testPropertyHasValue() {
        let uuidString1 = PerfectLib.UUID().string
        let dateString = DateExtras.date(Date(), toFormat: .DATETIME)

        let uploadRequest = UploadFileRequest(json: [
            UploadFileRequest.fileUUIDKey : uuidString1,
            UploadFileRequest.mimeTypeKey: "text/plain",
            UploadFileRequest.cloudFolderNameKey: "CloudFolder",
            UploadFileRequest.fileVersionKey: FileVersionInt(1),
            UploadFileRequest.masterVersionKey: MasterVersionInt(42),
            UploadFileRequest.creationDateKey: dateString,
            UploadFileRequest.updateDateKey: dateString
        ])
        
        XCTAssert(uploadRequest!.propertyHasValue(propertyName: UploadFileRequest.fileUUIDKey))
        XCTAssert(uploadRequest!.propertyHasValue(propertyName: UploadFileRequest.mimeTypeKey))
        XCTAssert(uploadRequest!.propertyHasValue(propertyName: UploadFileRequest.cloudFolderNameKey))
        XCTAssert(uploadRequest!.propertyHasValue(propertyName: UploadFileRequest.fileVersionKey))
        XCTAssert(uploadRequest!.propertyHasValue(propertyName: UploadFileRequest.masterVersionKey))
        XCTAssert(uploadRequest!.propertyHasValue(propertyName: UploadFileRequest.creationDateKey))
        XCTAssert(uploadRequest!.propertyHasValue(propertyName: UploadFileRequest.updateDateKey))
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

    // Modified from https://oleb.net/blog/2017/03/keeping-xctest-in-sync/
    func testLinuxTestSuiteIncludesAllTests() {
        #if os(macOS) || os(iOS) || os(tvOS) || os(watchOS)
            let thisClass = type(of: self)
            
            // Adding 1 to linuxCount because it doesn't have *this* test.
            let linuxCount = thisClass.allTests.count + 1
            
            let darwinCount = Int(thisClass
                .defaultTestSuite().testCaseCount)
            XCTAssertEqual(linuxCount, darwinCount,
                "\(darwinCount - linuxCount) test(s) are missing from allTests")
        #endif
    }
}

