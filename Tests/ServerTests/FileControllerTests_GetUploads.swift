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
import Foundation

class FileControllerTests_GetUploads: ServerTestCase, LinuxTestable {

    override func setUp() {
        super.setUp()
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }
    
    override func tearDown() {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
        super.tearDown()
    }
    
    func testForZeroUploads() {
        let deviceUUID = Foundation.UUID().uuidString
        self.addNewUser(deviceUUID:deviceUUID)
        self.getUploads(expectedFiles: [], deviceUUID:deviceUUID, expectedFileSizes: [:])
    }
    
    func testForOneUpload() {
        let deviceUUID = Foundation.UUID().uuidString
        guard let uploadResult = uploadTextFile(deviceUUID:deviceUUID) else {
            XCTFail()
            return
        }

        let expectedSizes = [
            uploadResult.request.fileUUID: uploadResult.fileSize
        ]
        
        self.getUploads(expectedFiles: [uploadResult.request], deviceUUID:deviceUUID, expectedFileSizes: expectedSizes)
    }
    
    func testForOneUploadButDoneTwice() {
        let deviceUUID = Foundation.UUID().uuidString
        guard let uploadResult = uploadTextFile(deviceUUID:deviceUUID), let sharingGroupId = uploadResult.sharingGroupId else {
            XCTFail()
            return
        }

        // Second upload-- shouldn't result in second entries in Upload table.
        _ = uploadTextFile(deviceUUID: deviceUUID, fileUUID: uploadResult.request.fileUUID, addUser: .no(sharingGroupId: sharingGroupId), fileVersion: uploadResult.request.fileVersion, masterVersion: uploadResult.request.masterVersion, appMetaData: uploadResult.request.appMetaData)
        
        let expectedSizes = [
            uploadResult.request.fileUUID: uploadResult.fileSize,
        ]
        
        self.getUploads(expectedFiles: [uploadResult.request], deviceUUID:deviceUUID, expectedFileSizes: expectedSizes)
    }
    
    func testForOneUploadButFromWrongDeviceUUID() {
        let deviceUUID = Foundation.UUID().uuidString
        _ = uploadTextFile(deviceUUID:deviceUUID)
        
        // This will do the GetUploads, but with a different deviceUUID, which will give empty result.
        self.getUploads(expectedFiles: [], expectedFileSizes: [:])
    }
    
    func testForTwoUploads() {
        let deviceUUID = Foundation.UUID().uuidString
        guard let uploadResult1 = uploadTextFile(deviceUUID:deviceUUID), let sharingGroupId = uploadResult1.sharingGroupId else {
            XCTFail()
            return
        }
        
        guard let uploadResult2 = uploadJPEGFile(deviceUUID:deviceUUID, addUser:.no(sharingGroupId: sharingGroupId)) else {
            XCTFail()
            return
        }

        let expectedSizes = [
            uploadResult1.request.fileUUID: uploadResult1.fileSize,
            uploadResult2.request.fileUUID: uploadResult2.fileSize
        ]
        
        self.getUploads(expectedFiles: [uploadResult1.request, uploadResult2.request], deviceUUID:deviceUUID, expectedFileSizes: expectedSizes)
    }
    
    func testForNoUploadsAfterDoneUploads() {
        let deviceUUID = Foundation.UUID().uuidString
        guard let uploadResult1 = uploadTextFile(deviceUUID:deviceUUID), let sharingGroupId = uploadResult1.sharingGroupId else {
            XCTFail()
            return
        }
        
        self.sendDoneUploads(expectedNumberOfUploads: 1, deviceUUID:deviceUUID, sharingGroupId: sharingGroupId)
        self.getUploads(expectedFiles: [], deviceUUID:deviceUUID, expectedFileSizes: [:])
    }
}

extension FileControllerTests_GetUploads {
    static var allTests : [(String, (FileControllerTests_GetUploads) -> () throws -> Void)] {
        return [
            ("testForZeroUploads", testForZeroUploads),
            ("testForOneUpload", testForOneUpload),
            ("testForOneUploadButDoneTwice", testForOneUploadButDoneTwice),
            ("testForOneUploadButFromWrongDeviceUUID", testForOneUploadButFromWrongDeviceUUID),
            ("testForTwoUploads", testForTwoUploads),
            ("testForNoUploadsAfterDoneUploads", testForNoUploadsAfterDoneUploads)
        ]
    }
    
    func testLinuxTestSuiteIncludesAllTests() {
        linuxTestSuiteIncludesAllTests(testType:FileControllerTests_GetUploads.self)
    }
}
