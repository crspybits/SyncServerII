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
        _ = FileIndexRepository.remove()
        _ = FileIndexRepository.create()
    }
    
    override func tearDown() {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
        super.tearDown()
    }

    func runUploadTest(data:Data, uploadRequest:UploadFileRequest, expectedUploadSize:Int64, updatedMasterVersionExpected:Int64? = nil) {
        self.performServerTest { expectation, googleCreds in
            let headers = self.setupHeaders(accessToken: googleCreds.accessToken)
            
            self.performRequest(route: ServerEndpoints.uploadFile, headers: headers, urlParameters: "?" + uploadRequest.urlParameters()!, body:data) { response, dict in
                Log.info("Status code: \(response!.statusCode)")
                XCTAssert(response!.statusCode == .OK, "Did not work on uploadFile request")
                XCTAssert(dict != nil)
                
                if let uploadResponse = UploadFileResponse(json: dict!) {
                    if updatedMasterVersionExpected == nil {
                        XCTAssert(uploadResponse.size != nil)
                        XCTAssert(uploadResponse.size == expectedUploadSize)
                    }
                    else {
                        XCTAssert(uploadResponse.masterVersionUpdate == updatedMasterVersionExpected)
                    }
                }
                else {
                    XCTFail()
                }
                
                let result = UploadRepository.lookup(key: .fileUUID(uploadRequest.fileUUID), modelInit: Upload.init)
                switch result {
                case .error(let error):
                    XCTFail("\(error)")
                    
                case .found(_):
                    if updatedMasterVersionExpected != nil {
                        XCTFail("No Upload Found")
                    }

                case .noObjectFound:
                    if updatedMasterVersionExpected == nil {
                        XCTFail("No Upload Found")
                    }
                }

                expectation.fulfill()
            }
        }
    }
    
    func uploadTextFile(deviceUUID:String = PerfectLib.UUID().string, addUser:Bool=true, updatedMasterVersionExpected:Int64? = nil) {
        if addUser {
            self.addNewUser()
        }
        
        let stringToUpload = "Hello World!"
        let data = stringToUpload.data(using: .utf8)
        
        let uploadRequest = UploadFileRequest(json: [
            UploadFileRequest.fileUUIDKey : PerfectLib.UUID().string,
            UploadFileRequest.mimeTypeKey: "text/plain",
            UploadFileRequest.cloudFolderNameKey: "CloudFolder",
            UploadFileRequest.deviceUUIDKey: deviceUUID,
            UploadFileRequest.fileVersionKey: "1",
            UploadFileRequest.masterVersionKey: "0"
        ])
        
        runUploadTest(data:data!, uploadRequest:uploadRequest!, expectedUploadSize:Int64(stringToUpload.characters.count), updatedMasterVersionExpected:updatedMasterVersionExpected)
    }
    
    func testUploadTextFile() {
        uploadTextFile()
    }
    
    func uploadJPEGFile(deviceUUID:String = PerfectLib.UUID().string, addUser:Bool=true) {
        if addUser {
            self.addNewUser()
        }
        
        let fileURL = URL(fileURLWithPath: "/tmp/Cat.jpg")
        let sizeOfCatFileInBytes:Int64 = 1162662
        let data = try! Data(contentsOf: fileURL)
        
        let uploadRequest = UploadFileRequest(json: [
            UploadFileRequest.fileUUIDKey : PerfectLib.UUID().string,
            UploadFileRequest.mimeTypeKey: "image/jpeg",
            UploadFileRequest.cloudFolderNameKey: testFolder,
            UploadFileRequest.fileVersionKey: "1",
            UploadFileRequest.deviceUUIDKey: deviceUUID,
            UploadFileRequest.masterVersionKey: "0"
        ])
        
        runUploadTest(data:data, uploadRequest:uploadRequest!, expectedUploadSize:sizeOfCatFileInBytes)
    }
    
    func testUploadJPEGFile() {
        uploadJPEGFile()
    }
    
    func sendDoneUploads(expectedNumberOfUploads:Int32?, deviceUUID:String = PerfectLib.UUID().string, updatedMasterVersionExpected:Int64? = nil) {
        self.performServerTest { expectation, googleCreds in
            let headers = self.setupHeaders(accessToken: googleCreds.accessToken)
            
            let doneUploadsRequest = DoneUploadsRequest(json: [
                DoneUploadsRequest.deviceUUIDKey: deviceUUID,
                DoneUploadsRequest.masterVersionKey : "0"
            ])
        
            self.performRequest(route: ServerEndpoints.doneUploads, headers: headers, urlParameters: "?" + doneUploadsRequest!.urlParameters()!, body:nil) { response, dict in
                Log.info("Status code: \(response!.statusCode)")
                XCTAssert(response!.statusCode == .OK, "Did not work on doneUploadsRequest request")
                XCTAssert(dict != nil)
                
                if let doneUploadsResponse = DoneUploadsResponse(json: dict!) {
                    XCTAssert(doneUploadsResponse.masterVersionUpdate == updatedMasterVersionExpected)
                    XCTAssert(doneUploadsResponse.numberUploadsTransferred == expectedNumberOfUploads)
                }
                else {
                    XCTFail()
                }
                
                expectation.fulfill()
            }
        }
    }
    
    // A test that causes a conflict with the master version on the server. Presumably this needs to take the form of (a) device1 uploading a file to the server, (b) device2 uploading a file, and finishing that upload (`DoneUploads` endpoint), and (c) device1 uploading a second file using its original master version.
    func testMasterVersionConflict1() {
        let deviceUUID1 = PerfectLib.UUID().string
        uploadTextFile(deviceUUID:deviceUUID1)
        
        let deviceUUID2 = PerfectLib.UUID().string
        uploadTextFile(deviceUUID:deviceUUID2, addUser:false)
        
        self.sendDoneUploads(expectedNumberOfUploads: 1, deviceUUID:deviceUUID2)
        
        uploadTextFile(deviceUUID:deviceUUID2, addUser:false, updatedMasterVersionExpected:1)
    }
    
    func testMasterVersionConflict2() {
        let deviceUUID1 = PerfectLib.UUID().string
        uploadTextFile(deviceUUID:deviceUUID1)
        
        let deviceUUID2 = PerfectLib.UUID().string
        uploadTextFile(deviceUUID:deviceUUID2, addUser:false)
        
        self.sendDoneUploads(expectedNumberOfUploads: 1, deviceUUID:deviceUUID1)
        
        self.sendDoneUploads(expectedNumberOfUploads: nil, deviceUUID:deviceUUID2, updatedMasterVersionExpected:1)
    }
    
    func testDoneUploadsWithNoUploads() {
        self.addNewUser()
        self.sendDoneUploads(expectedNumberOfUploads: 0)
    }
    
    func testDoneUploadsWithSingleUpload() {
        let deviceUUID = PerfectLib.UUID().string
        uploadTextFile(deviceUUID:deviceUUID)
        self.sendDoneUploads(expectedNumberOfUploads: 1, deviceUUID:deviceUUID)
    }
    
    func testDoneUploadsWithTwoUploads() {
        let deviceUUID = PerfectLib.UUID().string
        uploadTextFile(deviceUUID:deviceUUID)
        uploadJPEGFile(deviceUUID:deviceUUID, addUser:false)
        self.sendDoneUploads(expectedNumberOfUploads: 2, deviceUUID:deviceUUID)
    }
}
