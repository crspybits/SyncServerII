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
            UploadFileRequest.fileVersionKey: 1,
            UploadFileRequest.masterVersionKey: 42
        ])
        
        let fileVersion = valueFor(property: UploadFileRequest.fileVersionKey, of: uploadRequest! as Any) as? FileVersionInt
        XCTAssert(fileVersion == 1, "fileVersion = \(String(describing: fileVersion))")
        
        let masterVersion = valueFor(property: UploadFileRequest.masterVersionKey, of: uploadRequest!  as Any) as? MasterVersionInt
        XCTAssert(masterVersion == 42, "masterVersion = \(String(describing: masterVersion))")
  }

    func testURLParameters() {
        let uuidString1 = PerfectLib.UUID().string
        
        let uploadRequest = UploadFileRequest(json: [
            UploadFileRequest.fileUUIDKey : uuidString1,
            UploadFileRequest.mimeTypeKey: "text/plain",
            UploadFileRequest.cloudFolderNameKey: "CloudFolder",
            UploadFileRequest.fileVersionKey: 1,
            UploadFileRequest.masterVersionKey: 42
        ])
        
        let result = uploadRequest!.urlParameters()
        
        XCTAssert(result == "\(UploadFileRequest.fileUUIDKey)=\(uuidString1)&mimeType=text%2Fplain&\(UploadFileRequest.cloudFolderNameKey)=CloudFolder&\(UploadFileRequest.fileVersionKey)=1&\(UploadFileRequest.masterVersionKey)=42", "Result was: \(String(describing: result))")
    }
    
    func testURLParametersWithIntegersAsStrings() {
        let uuidString1 = PerfectLib.UUID().string
        
        let uploadRequest = UploadFileRequest(json: [
            UploadFileRequest.fileUUIDKey : uuidString1,
            UploadFileRequest.mimeTypeKey: "text/plain",
            UploadFileRequest.cloudFolderNameKey: "CloudFolder",
            UploadFileRequest.fileVersionKey: "1",
            UploadFileRequest.masterVersionKey: "42"
        ])
        
        let result = uploadRequest!.urlParameters()
        
        XCTAssert(result == "\(UploadFileRequest.fileUUIDKey)=\(uuidString1)&mimeType=text%2Fplain&\(UploadFileRequest.cloudFolderNameKey)=CloudFolder&\(UploadFileRequest.fileVersionKey)=1&\(UploadFileRequest.masterVersionKey)=42", "Result was: \(String(describing: result))")
    }
    
    func testURLParametersForUploadDeletion() {
        let uuidString = PerfectLib.UUID().string

        let uploadDeletionRequest = UploadDeletionRequest(json: [
            UploadDeletionRequest.fileUUIDKey: uuidString,
            UploadDeletionRequest.fileVersionKey: 99,
            UploadDeletionRequest.masterVersionKey: 23,
            UploadDeletionRequest.actualDeletionKey: 1
        ])
        
        let result = uploadDeletionRequest!.urlParameters()
        
        let x:Int?=1
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
            UploadFileRequest.cloudFolderNameKey: "CloudFolder",
            UploadFileRequest.fileVersionKey: 1,
            UploadFileRequest.masterVersionKey: 42
        ])
        XCTAssert(uploadRequest == nil)
    }
    
    func testPropertyHasValue() {
        let uuidString1 = PerfectLib.UUID().string
        
        let uploadRequest = UploadFileRequest(json: [
            UploadFileRequest.fileUUIDKey : uuidString1,
            UploadFileRequest.mimeTypeKey: "text/plain",
            UploadFileRequest.cloudFolderNameKey: "CloudFolder",
            UploadFileRequest.fileVersionKey: 1,
            UploadFileRequest.masterVersionKey: 42
        ])
        
        XCTAssert(uploadRequest!.propertyHasValue(propertyName: UploadFileRequest.fileUUIDKey))
        XCTAssert(uploadRequest!.propertyHasValue(propertyName: UploadFileRequest.mimeTypeKey))
        XCTAssert(uploadRequest!.propertyHasValue(propertyName: UploadFileRequest.cloudFolderNameKey))
        XCTAssert(uploadRequest!.propertyHasValue(propertyName: UploadFileRequest.fileVersionKey))
        XCTAssert(uploadRequest!.propertyHasValue(propertyName: UploadFileRequest.masterVersionKey))
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
}
