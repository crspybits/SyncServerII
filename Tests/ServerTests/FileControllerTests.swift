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
import Foundation
import SyncServerShared

class FileControllerTests: ServerTestCase, LinuxTestable {

    override func setUp() {
        super.setUp()
    }
    
    override func tearDown() {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
        super.tearDown()
    }
      
    // A test that causes a conflict with the master version on the server. Presumably this needs to take the form of (a) device1 uploading a file to the server, (b) device2 uploading a file, and finishing that upload (`DoneUploads` endpoint), and (c) device1 uploading a second file using its original master version.
    func testMasterVersionConflict1() {
        let deviceUUID1 = Foundation.UUID().uuidString
        guard let uploadResult = uploadTextFile(deviceUUID:deviceUUID1), let sharingGroupId = uploadResult.sharingGroupId else {
            XCTFail()
            return
        }
        
        let deviceUUID2 = Foundation.UUID().uuidString
        guard let _ = uploadTextFile(deviceUUID:deviceUUID2, addUser:.no(sharingGroupId: sharingGroupId)) else {
            XCTFail()
            return
        }
        
        self.sendDoneUploads(expectedNumberOfUploads: 1, deviceUUID:deviceUUID2, sharingGroupId: sharingGroupId)
        
        guard let _ = uploadTextFile(deviceUUID:deviceUUID2, addUser:.no(sharingGroupId: sharingGroupId), updatedMasterVersionExpected:1) else {
            XCTFail()
            return
        }
    }
    
    func testMasterVersionConflict2() {
        let deviceUUID1 = Foundation.UUID().uuidString
        guard let uploadResult = uploadTextFile(deviceUUID:deviceUUID1), let sharingGroupId = uploadResult.sharingGroupId else {
            XCTFail()
            return
        }
        
        let deviceUUID2 = Foundation.UUID().uuidString
        guard let _ = uploadTextFile(deviceUUID:deviceUUID2, addUser:.no(sharingGroupId: sharingGroupId)) else {
            XCTFail()
            return
        }
        
        self.sendDoneUploads(expectedNumberOfUploads: 1, deviceUUID:deviceUUID1, sharingGroupId: sharingGroupId)
        
        // No uploads should have been successfully finished, i.e., expectedNumberOfUploads = nil, and the updatedMasterVersion should have been updated to 1.
        self.sendDoneUploads(expectedNumberOfUploads: nil, deviceUUID:deviceUUID2, updatedMasterVersionExpected:1, sharingGroupId: sharingGroupId)
    }

    func testIndexWithNoFiles() {
        let deviceUUID = Foundation.UUID().uuidString

        guard let addUserResponse = self.addNewUser(deviceUUID:deviceUUID),
            let sharingGroupId = addUserResponse.sharingGroupId else {
            XCTFail()
            return
        }
        
        self.getIndex(expectedFiles: [], masterVersionExpected: 0, expectedFileSizes: [:], sharingGroupId: sharingGroupId)
    }

    func testGetIndexForOnlySharingGroupsWorks() {
        let deviceUUID = Foundation.UUID().uuidString
        
        guard let addUserResponse = addNewUser(deviceUUID:deviceUUID),
            let sharingGroupId = addUserResponse.sharingGroupId else {
            XCTFail()
            return
        }
        
        guard let (files, sharingGroups) = getIndex() else {
            XCTFail()
            return
        }
        
        XCTAssert(files == nil)
        
        guard sharingGroups.count == 1 else {
            XCTFail()
            return
        }
        
        XCTAssert(sharingGroups[0].sharingGroupId == sharingGroupId)
        XCTAssert(sharingGroups[0].sharingGroupName == nil)
        XCTAssert(sharingGroups[0].deleted == false)
    }
    
    func testIndexWithOneFile() {
        let deviceUUID = Foundation.UUID().uuidString
        guard let uploadResult = uploadTextFile(deviceUUID:deviceUUID), let sharingGroupId = uploadResult.sharingGroupId else {
            XCTFail()
            return
        }
        
        // Have to do a DoneUploads to transfer the files into the FileIndex
        self.sendDoneUploads(expectedNumberOfUploads: 1, deviceUUID:deviceUUID, sharingGroupId: sharingGroupId)

        let expectedSizes = [
            uploadResult.request.fileUUID: uploadResult.fileSize,
        ]
        
        self.getIndex(expectedFiles: [uploadResult.request], masterVersionExpected: 1, expectedFileSizes: expectedSizes, sharingGroupId: sharingGroupId)
        
        guard let (files, sharingGroups) = getIndex(sharingGroupId: sharingGroupId) else {
            XCTFail()
            return
        }
        
        XCTAssert(files != nil)
        
        guard sharingGroups.count == 1, sharingGroups[0].sharingGroupId == sharingGroupId,  sharingGroups[0].sharingGroupName == nil,
            sharingGroups[0].deleted == false
            else {
            XCTFail()
            return
        }
    }
    
    func testIndexWithTwoFiles() {
        let deviceUUID = Foundation.UUID().uuidString
        guard let uploadResult1 = uploadTextFile(deviceUUID:deviceUUID), let sharingGroupId = uploadResult1.sharingGroupId else {
            XCTFail()
            return
        }
        
        guard let uploadResult2 = uploadJPEGFile(deviceUUID:deviceUUID, addUser:.no(sharingGroupId: sharingGroupId)) else {
            XCTFail()
            return
        }
        
        // Have to do a DoneUploads to transfer the files into the FileIndex
        self.sendDoneUploads(expectedNumberOfUploads: 2, deviceUUID:deviceUUID, sharingGroupId: sharingGroupId)

        let expectedSizes = [
            uploadResult1.request.fileUUID: uploadResult1.fileSize,
            uploadResult2.request.fileUUID: uploadResult2.fileSize
        ]
        
        self.getIndex(expectedFiles: [uploadResult1.request, uploadResult2.request],masterVersionExpected: 1, expectedFileSizes: expectedSizes, sharingGroupId: sharingGroupId)
    }
        
    func testDownloadFileTextSucceeds() {
        downloadTextFile(masterVersionExpectedWithDownload: 1)
    }
    
    func testDownloadFileTextWhereMasterVersionDiffersFails() {
        downloadTextFile(masterVersionExpectedWithDownload: 0, expectUpdatedMasterUpdate:true)
    }
    
    func testDownloadFileTextWithAppMetaDataSucceeds() {
        downloadTextFile(masterVersionExpectedWithDownload: 1,
            appMetaData:AppMetaData(version: 0, contents: "{ \"foo\": \"bar\" }"))
    }
    
    func testDownloadFileTextWithDifferentDownloadVersion() {
        downloadTextFile(masterVersionExpectedWithDownload: 1, downloadFileVersion:1, expectedError: true)
    }
    
    func testIndexWithFakeSharingGroupIdFails() {
        let deviceUUID = Foundation.UUID().uuidString
        guard let uploadResult = uploadTextFile(deviceUUID:deviceUUID), let sharingGroupId = uploadResult.sharingGroupId else {
            XCTFail()
            return
        }
        
        // Have to do a DoneUploads to transfer the files into the FileIndex
        self.sendDoneUploads(expectedNumberOfUploads: 1, deviceUUID:deviceUUID, sharingGroupId: sharingGroupId)

        let expectedSizes = [
            uploadResult.request.fileUUID: uploadResult.fileSize,
        ]
        
        let invalidSharingGroupId: SharingGroupId = 100
        
        self.getIndex(expectedFiles: [uploadResult.request], masterVersionExpected: 1, expectedFileSizes: expectedSizes, sharingGroupId: invalidSharingGroupId, errorExpected: true)
    }
    
    func testIndexWithBadSharingGroupIdFails() {
        let deviceUUID = Foundation.UUID().uuidString
        guard let uploadResult = uploadTextFile(deviceUUID:deviceUUID), let sharingGroupId = uploadResult.sharingGroupId else {
            XCTFail()
            return
        }
        
        // Have to do a DoneUploads to transfer the files into the FileIndex
        self.sendDoneUploads(expectedNumberOfUploads: 1, deviceUUID:deviceUUID, sharingGroupId: sharingGroupId)

        let expectedSizes = [
            uploadResult.request.fileUUID: uploadResult.fileSize,
        ]
        
        guard let workingButBadSharingGroupId = addSharingGroup() else {
            XCTFail()
            return
        }
        
        self.getIndex(expectedFiles: [uploadResult.request], masterVersionExpected: 1, expectedFileSizes: expectedSizes, sharingGroupId: workingButBadSharingGroupId, errorExpected: true)
    }
    
    // TODO: *0*: Make sure we're not trying to download a file that has already been deleted.
    
    // TODO: *1* Make sure its an error for a different user to download our file even if they have the fileUUID and fileVersion.
    
    // TODO: *1* Test that two concurrent downloads work.
}

extension FileControllerTests {
    static var allTests : [(String, (FileControllerTests) -> () throws -> Void)] {
        return [
            ("testMasterVersionConflict1", testMasterVersionConflict1),
            ("testMasterVersionConflict2", testMasterVersionConflict2),
            ("testIndexWithNoFiles", testIndexWithNoFiles),
            ("testIndexWithOneFile", testIndexWithOneFile),
            ("testIndexWithTwoFiles", testIndexWithTwoFiles),
            ("testDownloadFileTextSucceeds", testDownloadFileTextSucceeds),
            ("testDownloadFileTextWhereMasterVersionDiffersFails", testDownloadFileTextWhereMasterVersionDiffersFails),
            ("testDownloadFileTextWithAppMetaDataSucceeds", testDownloadFileTextWithAppMetaDataSucceeds),
            ("testDownloadFileTextWithDifferentDownloadVersion", testDownloadFileTextWithDifferentDownloadVersion),
            ("testIndexWithFakeSharingGroupIdFails", testIndexWithFakeSharingGroupIdFails),
            ("testIndexWithBadSharingGroupIdFails", testIndexWithBadSharingGroupIdFails),
            ("testGetIndexForOnlySharingGroupsWorks", testGetIndexForOnlySharingGroupsWorks)
        ]
    }
    
    func testLinuxTestSuiteIncludesAllTests() {
        linuxTestSuiteIncludesAllTests(testType:FileControllerTests.self)
    }
}


