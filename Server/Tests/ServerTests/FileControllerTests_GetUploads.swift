//
//  FileControllerTests_GetUploads.swift
//  Server
//
//  Created by Christopher Prince on 2/18/17.
//
//

import XCTest
@testable import Server
import LoggerAPI
import PerfectLib

class FileControllerTests_GetUploads: ServerTestCase {

    override func setUp() {
        super.setUp()
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }
    
    override func tearDown() {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
        super.tearDown()
    }

    func getUploads(expectedFiles:[UploadFileRequest], deviceUUID:String = PerfectLib.UUID().string,expectedFileSizes: [String: Int64]) {
    
        XCTAssert(expectedFiles.count == expectedFileSizes.count)
        
        self.performServerTest { expectation, googleCreds in
            let headers = self.setupHeaders(accessToken: googleCreds.accessToken, deviceUUID:deviceUUID)
            
            self.performRequest(route: ServerEndpoints.getUploads, headers: headers, body:nil) { response, dict in
                Log.info("Status code: \(response!.statusCode)")
                XCTAssert(response!.statusCode == .OK, "Did not work on getUploadsRequest request")
                XCTAssert(dict != nil)
                
                if let getUploadsResponse = GetUploadsResponse(json: dict!) {
                    if getUploadsResponse.uploads == nil {
                        XCTAssert(expectedFiles.count == 0)
                        XCTAssert(expectedFileSizes.count == 0)
                    }
                    else {
                        XCTAssert(getUploadsResponse.uploads!.count == expectedFiles.count)
                        
                        _ = getUploadsResponse.uploads!.map { fileInfo in
                            Log.info("fileInfo: \(fileInfo)")
                            
                            let filterResult = expectedFiles.filter { uploadFileRequest in
                                uploadFileRequest.fileUUID == fileInfo.fileUUID
                            }
                            
                            XCTAssert(filterResult.count == 1)
                            let expectedFile = filterResult[0]
                            
                            XCTAssert(expectedFile.appMetaData == fileInfo.appMetaData)
                            XCTAssert(expectedFile.fileUUID == fileInfo.fileUUID)
                            XCTAssert(expectedFile.fileVersion == fileInfo.fileVersion)
                            XCTAssert(expectedFile.mimeType == fileInfo.mimeType)
                            XCTAssert(fileInfo.deleted == false)
                            
                            XCTAssert(expectedFileSizes[fileInfo.fileUUID] == fileInfo.fileSizeBytes)
                        }
                    }
                }
                else {
                    XCTFail()
                }
                
                expectation.fulfill()
            }
        }
    }
    
    func testForZeroUploads() {
        let deviceUUID = PerfectLib.UUID().string
        self.addNewUser(deviceUUID:deviceUUID)
        self.getUploads(expectedFiles: [], deviceUUID:deviceUUID, expectedFileSizes: [:])
    }
    
    func testForOneUpload() {
        let deviceUUID = PerfectLib.UUID().string
        let (uploadRequest1, fileSize1) = uploadTextFile(deviceUUID:deviceUUID)

        let expectedSizes = [
            uploadRequest1.fileUUID: fileSize1,
        ]
        
        self.getUploads(expectedFiles: [uploadRequest1], deviceUUID:deviceUUID, expectedFileSizes: expectedSizes)
    }
    
    func testForOneUploadButFromWrongDeviceUUID() {
        let deviceUUID = PerfectLib.UUID().string
        _ = uploadTextFile(deviceUUID:deviceUUID)
        
        // This will do the GetUploads, but with a different deviceUUID, which will give empty result.
        self.getUploads(expectedFiles: [], expectedFileSizes: [:])
    }
    
    func testForTwoUploads() {
        //let (uploadRequest, fileSize) = uploadTextFile(deviceUUID:deviceUUID)
        
        let deviceUUID = PerfectLib.UUID().string
        let (uploadRequest1, fileSize1) = uploadTextFile(deviceUUID:deviceUUID)
        let (uploadRequest2, fileSize2) = uploadJPEGFile(deviceUUID:deviceUUID, addUser:false)

        let expectedSizes = [
            uploadRequest1.fileUUID: fileSize1,
            uploadRequest2.fileUUID: fileSize2
        ]
        
        self.getUploads(expectedFiles: [uploadRequest1, uploadRequest2], deviceUUID:deviceUUID, expectedFileSizes: expectedSizes)
    }
    
    func testForNoUploadsAfterDoneUploads() {
        let deviceUUID = PerfectLib.UUID().string
        _ = uploadTextFile(deviceUUID:deviceUUID)
        self.sendDoneUploads(expectedNumberOfUploads: 1, deviceUUID:deviceUUID)
        self.getUploads(expectedFiles: [], deviceUUID:deviceUUID, expectedFileSizes: [:])
    }
}
