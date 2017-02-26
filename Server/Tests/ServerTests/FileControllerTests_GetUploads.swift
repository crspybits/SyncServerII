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