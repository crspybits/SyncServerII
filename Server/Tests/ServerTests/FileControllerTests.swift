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

class FileControllerTests: ServerTestCase {

    let testFolder = "Test.Folder"

    override func setUp() {
        super.setUp()
        _ = UserRepository.remove()
        _ = UserRepository.create()
    }
    
    override func tearDown() {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
        super.tearDown()
    }

    func testUploadTextFile() {
        self.addNewUser()
        
        let stringToUpload = "Hello World!"
        let data = stringToUpload.data(using: .utf8)
        
        // TODO: File name should actually be a UUID.
        
        let uploadRequest = UploadFileRequest(json: [
            UploadFileRequest.fileNameKey: "HelloWorld.txt",
            UploadFileRequest.mimeTypeKey: "text/plain",
            UploadFileRequest.folderNameKey: testFolder
        ])
                
        self.performServerTest { expectation, googleCreds in
            let headers = self.setupHeaders(accessToken: googleCreds.accessToken)
            
            self.performRequest(route: ServerEndpoints.uploadFile, headers: headers, urlParameters: "?" + uploadRequest!.urlParameters()!, body:data) { response, dict in
                Log.info("Status code: \(response!.statusCode)")
                XCTAssert(response!.statusCode == .OK, "Did not work on uploadFile request")
                expectation.fulfill()
            }
        }
    }
    
    func testUploadJPEGFile() {
        self.addNewUser()

        let fileURL = URL(fileURLWithPath: "/tmp/Cat.jpg")
        let data = try! Data(contentsOf: fileURL)
        
        // TODO: File name should actually be a UUID.
        
        let uploadRequest = UploadFileRequest(json: [
            UploadFileRequest.fileNameKey: "Cat",
            UploadFileRequest.mimeTypeKey: "image/jpeg",
            UploadFileRequest.folderNameKey: testFolder
        ])
                
        self.performServerTest { expectation, googleCreds in
            let headers = self.setupHeaders(accessToken: googleCreds.accessToken)
            
            self.performRequest(route: ServerEndpoints.uploadFile, headers: headers, urlParameters: "?" + uploadRequest!.urlParameters()!, body:data) { response, dict in
                Log.info("Status code: \(response!.statusCode)")
                XCTAssert(response!.statusCode == .OK, "Did not work on uploadFile request")
                expectation.fulfill()
            }
        }
    }
}
