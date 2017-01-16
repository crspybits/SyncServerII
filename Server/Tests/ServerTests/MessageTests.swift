//
//  MessageTests.swift
//  Server
//
//  Created by Christopher Prince on 1/15/17.
//
//

import XCTest
@testable import Server

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
        let uploadRequest = UploadFileRequest(json: [
            UploadFileRequest.fileNameKey: "Foobar2",
            UploadFileRequest.mimeTypeKey: "text/plain"
        ])
        let result = uploadRequest!.urlParameters()
        XCTAssert(result == "fileName=Foobar2&mimeType=text/plain", "Result was: \(result)")
    }
}
