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
        let uuidString1 = PerfectLib.UUID().string
        let uuidString2 = PerfectLib.UUID().string

        let uploadRequest = UploadFileRequest(json: [
            UploadFileRequest.fileUUIDKey : uuidString1,
            UploadFileRequest.mimeTypeKey: "text/plain",
            UploadFileRequest.cloudFolderNameKey: "CloudFolder",
            UploadFileRequest.deviceUUIDKey: uuidString2,
            UploadFileRequest.versionKey: "1"
        ])
        
        let result = uploadRequest!.urlParameters()
        
        XCTAssert(result == "\(UploadFileRequest.fileUUIDKey)=\(uuidString1)&mimeType=text/plain&\(UploadFileRequest.cloudFolderNameKey)=CloudFolder&\(UploadFileRequest.deviceUUIDKey)=\(uuidString2)&\(UploadFileRequest.versionKey)=1", "Result was: \(result)")
    }
    
    func testBadUUIDForFileName() {
        let uuidString2 = PerfectLib.UUID().string

        let uploadRequest = UploadFileRequest(json: [
            UploadFileRequest.fileUUIDKey : "foobar",
            UploadFileRequest.mimeTypeKey: "text/plain",
            UploadFileRequest.cloudFolderNameKey: "CloudFolder",
            UploadFileRequest.versionKey: "1",
            UploadFileRequest.deviceUUIDKey: uuidString2,
        ])
        XCTAssert(uploadRequest == nil)
    }
}
