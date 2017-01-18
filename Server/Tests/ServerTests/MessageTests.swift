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

class MessageTests: ServerTestCase {

    override func setUp() {
        super.setUp()
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }
    
    override func tearDown() {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
        super.tearDown()
    }

    func testURLParameters() {
        let uuidString = PerfectLib.UUID().string
        let uploadRequest = UploadFileRequest(json: [
            UploadFileRequest.cloudFileUUIDKey : uuidString,
            UploadFileRequest.mimeTypeKey: "text/plain",
            UploadFileRequest.cloudFolderNameKey: "CloudFolder"
        ])
        let result = uploadRequest!.urlParameters()
        XCTAssert(result == "\(UploadFileRequest.cloudFileUUIDKey)=\(uuidString)&mimeType=text/plain&\(UploadFileRequest.cloudFolderNameKey)=CloudFolder", "Result was: \(result)")
    }
    
    func testBadUUIDForFileName() {
        let uploadRequest = UploadFileRequest(json: [
            UploadFileRequest.cloudFileUUIDKey : "foobar",
            UploadFileRequest.mimeTypeKey: "text/plain",
            UploadFileRequest.cloudFolderNameKey: "CloudFolder"
        ])
        XCTAssert(uploadRequest == nil)
    }
}
