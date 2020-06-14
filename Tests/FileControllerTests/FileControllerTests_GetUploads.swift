//
//  FileControllerTests_GetUploads.swift
//  Server
//
//  Created by Christopher Prince on 2/18/17.
//
//

import XCTest
@testable import Server
@testable import TestsCommon
import LoggerAPI
import Foundation
import ServerShared

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
        let sharingGroupUUID = Foundation.UUID().uuidString

        guard let _ = self.addNewUser(sharingGroupUUID: sharingGroupUUID, deviceUUID:deviceUUID) else {
            XCTFail()
            return
        }
        
        self.getUploads(expectedFiles: [], deviceUUID:deviceUUID, expectedCheckSums: [:], sharingGroupUUID: sharingGroupUUID)
    }
    
    func testForOneUpload() {
        let deviceUUID = Foundation.UUID().uuidString
        guard let uploadResult = uploadTextFile(deviceUUID:deviceUUID),
            let sharingGroupUUID = uploadResult.sharingGroupUUID else {
            XCTFail()
            return
        }

        let expectedCheckSums = [
            uploadResult.request.fileUUID!: uploadResult.checkSum
        ]
        
        self.getUploads(expectedFiles: [uploadResult.request], deviceUUID:deviceUUID, expectedCheckSums: expectedCheckSums, sharingGroupUUID: sharingGroupUUID)
    }

    func testForOneUploadButDoneTwice() {
        let deviceUUID = Foundation.UUID().uuidString
        guard let uploadResult = uploadTextFile(deviceUUID:deviceUUID),
            let sharingGroupUUID = uploadResult.sharingGroupUUID else {
            XCTFail()
            return
        }

        // Second upload-- shouldn't result in second entries in Upload table.
        guard let _ = uploadTextFile(deviceUUID: deviceUUID, fileUUID: uploadResult.request.fileUUID, addUser: .no(sharingGroupUUID: sharingGroupUUID), appMetaData: uploadResult.request.appMetaData) else {
            XCTFail()
            return
        }
        
        let expectedCheckSums = [
            uploadResult.request.fileUUID!: uploadResult.checkSum,
        ]
        
        self.getUploads(expectedFiles: [uploadResult.request], deviceUUID:deviceUUID, expectedCheckSums: expectedCheckSums, sharingGroupUUID: sharingGroupUUID)
    }
    
    func testForOneUploadButFromWrongDeviceUUID() {
        let deviceUUID = Foundation.UUID().uuidString
        
        guard let uploadResult = uploadTextFile(deviceUUID:deviceUUID),
            let sharingGroupUUID = uploadResult.sharingGroupUUID else {
            XCTFail()
            return
        }
        
        // This will do the GetUploads, but with a different deviceUUID, which will give empty result.
        self.getUploads(expectedFiles: [], expectedCheckSums: [:], sharingGroupUUID:sharingGroupUUID)
    }
    
    func testForTwoUploads() {
        let deviceUUID = Foundation.UUID().uuidString
        guard let uploadResult1 = uploadTextFile(deviceUUID:deviceUUID),
            let sharingGroupUUID = uploadResult1.sharingGroupUUID else {
            XCTFail()
            return
        }
        
        guard let uploadResult2 = uploadJPEGFile(deviceUUID:deviceUUID, addUser:.no(sharingGroupUUID: sharingGroupUUID)) else {
            XCTFail()
            return
        }

        let expectedCheckSums = [
            uploadResult1.request.fileUUID!: uploadResult1.checkSum,
            uploadResult2.request.fileUUID!: uploadResult2.checkSum
        ]
        
        self.getUploads(expectedFiles: [uploadResult1.request, uploadResult2.request], deviceUUID:deviceUUID, expectedCheckSums: expectedCheckSums, sharingGroupUUID: sharingGroupUUID)
    }
    
    func testForNoUploadsAfterDoneUploads() {
        let deviceUUID = Foundation.UUID().uuidString
        guard let uploadResult1 = uploadTextFile(deviceUUID:deviceUUID),
            let sharingGroupUUID = uploadResult1.sharingGroupUUID else {
            XCTFail()
            return
        }
        
        self.sendDoneUploads(expectedNumberOfUploads: 1, deviceUUID:deviceUUID, sharingGroupUUID: sharingGroupUUID)
        self.getUploads(expectedFiles: [], deviceUUID:deviceUUID, expectedCheckSums: [:], sharingGroupUUID: sharingGroupUUID)
    }
    
    func testFakeSharingGroupWithGetUploadsFails() {
        let deviceUUID = Foundation.UUID().uuidString
        guard let uploadResult1 = uploadTextFile(deviceUUID:deviceUUID),
            let sharingGroupUUID = uploadResult1.sharingGroupUUID else {
            XCTFail()
            return
        }
        
        let invalidSharingGroupUUID = UUID().uuidString

        self.sendDoneUploads(expectedNumberOfUploads: 1, deviceUUID:deviceUUID, sharingGroupUUID: sharingGroupUUID)
        self.getUploads(expectedFiles: [], deviceUUID:deviceUUID, expectedCheckSums: [:], sharingGroupUUID: invalidSharingGroupUUID, errorExpected: true)
    }
    
    func testBadSharingGroupWithGetUploadsFails() {
        let deviceUUID = Foundation.UUID().uuidString
        guard let uploadResult1 = uploadTextFile(deviceUUID:deviceUUID),
            let sharingGroupUUID = uploadResult1.sharingGroupUUID else {
            XCTFail()
            return
        }
        
        let workingButBadSharingGroupUUID = UUID().uuidString
        guard addSharingGroup(sharingGroupUUID: workingButBadSharingGroupUUID) else {
            XCTFail()
            return
        }
        
        self.sendDoneUploads(expectedNumberOfUploads: 1, deviceUUID:deviceUUID, sharingGroupUUID: sharingGroupUUID)
        self.getUploads(expectedFiles: [], deviceUUID:deviceUUID, expectedCheckSums: [:], sharingGroupUUID: workingButBadSharingGroupUUID, errorExpected: true)
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
            ("testForNoUploadsAfterDoneUploads", testForNoUploadsAfterDoneUploads),
            ("testBadSharingGroupWithGetUploadsFails", testBadSharingGroupWithGetUploadsFails),
            ("testFakeSharingGroupWithGetUploadsFails", testFakeSharingGroupWithGetUploadsFails)
        ]
    }
    
    func testLinuxTestSuiteIncludesAllTests() {
        linuxTestSuiteIncludesAllTests(testType:FileControllerTests_GetUploads.self)
    }
}
