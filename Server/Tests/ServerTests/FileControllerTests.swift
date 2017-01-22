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
import PerfectLib

class FileControllerTests: ServerTestCase {

    let testFolder = "Test.Folder"

    override func setUp() {
        super.setUp()
        _ = UserRepository.remove()
        _ = UserRepository.create()
        _ = UploadRepository.remove()
        _ = UploadRepository.create()
        _ = MasterVersionRepository.remove()
        _ = MasterVersionRepository.create()
    }
    
    override func tearDown() {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
        super.tearDown()
    }

    func runUploadTest(data:Data, uploadRequest:UploadFileRequest, expectedUploadSize:Int64) {
        self.performServerTest { expectation, googleCreds in
            let headers = self.setupHeaders(accessToken: googleCreds.accessToken)
            
            self.performRequest(route: ServerEndpoints.uploadFile, headers: headers, urlParameters: "?" + uploadRequest.urlParameters()!, body:data) { response, dict in
                Log.info("Status code: \(response!.statusCode)")
                XCTAssert(response!.statusCode == .OK, "Did not work on uploadFile request")
                XCTAssert(dict != nil)
                
                if let uploadResponse = UploadFileResponse(json: dict!) {
                    XCTAssert(uploadResponse.size != nil)
                    XCTAssert(uploadResponse.size == expectedUploadSize)
                }
                else {
                    XCTFail()
                }
                
                let result = UploadRepository.lookup(key: .fileUUID(uploadRequest.fileUUID), modelInit: Upload.init)
                switch result {
                case .error(let error):
                    XCTFail("\(error)")
                    
                case .found(_):
                    break

                case .noObjectFound:
                    XCTFail("No Upload Found")
                }

                expectation.fulfill()
            }
        }
    }
    
    func testUploadTextFile() {
        self.addNewUser()
        
        let stringToUpload = "Hello World!"
        let data = stringToUpload.data(using: .utf8)
        
        let uploadRequest = UploadFileRequest(json: [
            UploadFileRequest.fileUUIDKey : PerfectLib.UUID().string,
            UploadFileRequest.mimeTypeKey: "text/plain",
            UploadFileRequest.cloudFolderNameKey: "CloudFolder",
            UploadFileRequest.deviceUUIDKey: PerfectLib.UUID().string,
            UploadFileRequest.fileVersionKey: "1",
            UploadFileRequest.masterVersionKey: "0"
        ])
        
        runUploadTest(data:data!, uploadRequest:uploadRequest!, expectedUploadSize:Int64(stringToUpload.characters.count))
    }
    
    func testUploadJPEGFile() {
        self.addNewUser()

        let fileURL = URL(fileURLWithPath: "/tmp/Cat.jpg")
        let sizeOfCatFileInBytes:Int64 = 1162662
        let data = try! Data(contentsOf: fileURL)
        
        let uploadRequest = UploadFileRequest(json: [
            UploadFileRequest.fileUUIDKey : PerfectLib.UUID().string,
            UploadFileRequest.mimeTypeKey: "image/jpeg",
            UploadFileRequest.cloudFolderNameKey: testFolder,
            UploadFileRequest.fileVersionKey: "1",
            UploadFileRequest.deviceUUIDKey: PerfectLib.UUID().string,
            UploadFileRequest.masterVersionKey: "0"
        ])
        
        runUploadTest(data:data, uploadRequest:uploadRequest!, expectedUploadSize:sizeOfCatFileInBytes)
    }
    
    // TODO: A test that causes a conflict with the master version on the server. Presumably this needs to take the form of (a) device1 uploading a file to the server, (b) device2 uploading a file, and finishing that upload (`DoneUploads` endpoint), and (c) device1 uploading a second file using its original master version.
    func testMasterVersionUpdate() {
    }
    
    func testDoneUploadsWithNoUploads() {
    }
    
    func testDoneUploadsWithSingleUpload() {
    }
    
    func testDoneUploadsWithTwoUploads() {
    }
}
