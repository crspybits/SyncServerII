//
//  FileControllerTests_UploadDeletion.swift
//  Server
//
//  Created by Christopher Prince on 2/18/17.
//
//

import XCTest
@testable import Server
import LoggerAPI
import Foundation
import SyncServerShared
import PerfectLib

class FileControllerTests_UploadDeletion: ServerTestCase {

    override func setUp() {
        super.setUp()
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }
    
    override func tearDown() {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
        super.tearDown()
    }

    // TODO: *1* To test these it would be best to have a debugging endpoint or other service where we can test to see if the file is present in cloud storage.
    
    // TODO: *1* Also useful would be a service that lets us directly delete a file from cloud storage-- to simulate errors in file deletion.

    func testThatUploadDeletionTransfersToUploads() {
        let deviceUUID = PerfectLib.UUID().string
        let (uploadRequest, _) = uploadTextFile(deviceUUID:deviceUUID)
        
        self.sendDoneUploads(expectedNumberOfUploads: 1, deviceUUID:deviceUUID)
        
        let uploadDeletionRequest = UploadDeletionRequest(json: [
            UploadDeletionRequest.fileUUIDKey: uploadRequest.fileUUID,
            UploadDeletionRequest.fileVersionKey: uploadRequest.fileVersion,
            UploadDeletionRequest.masterVersionKey: uploadRequest.masterVersion + 1
        ])!
        
        uploadDeletion(uploadDeletionRequest: uploadDeletionRequest, deviceUUID: deviceUUID, addUser: false)

        let expectedDeletionState = [
            uploadRequest.fileUUID: true,
        ]
        
        self.getUploads(expectedFiles: [uploadRequest], deviceUUID:deviceUUID, matchOptionals: false, expectedDeletionState:expectedDeletionState)
        
        self.sendDoneUploads(expectedNumberOfUploads: 1, deviceUUID:deviceUUID, masterVersion: uploadRequest.masterVersion + 1)
        
        self.getUploads(expectedFiles: [], deviceUUID:deviceUUID, matchOptionals: false)
    }
    
    func testThatCombinedUploadDeletionAndFileUploadWork() {
        let deviceUUID = PerfectLib.UUID().string
        let (uploadRequest, fileSize) = uploadTextFile(deviceUUID:deviceUUID)
        
        self.sendDoneUploads(expectedNumberOfUploads: 1, deviceUUID:deviceUUID)
        
        let uploadDeletionRequest = UploadDeletionRequest(json: [
            UploadDeletionRequest.fileUUIDKey: uploadRequest.fileUUID,
            UploadDeletionRequest.fileVersionKey: uploadRequest.fileVersion,
            UploadDeletionRequest.masterVersionKey: uploadRequest.masterVersion + 1
        ])!
        
        uploadDeletion(uploadDeletionRequest: uploadDeletionRequest, deviceUUID: deviceUUID, addUser: false)
        
        let expectedDeletionState = [
            uploadRequest.fileUUID: true,
        ]
        
        self.getUploads(expectedFiles: [uploadRequest], deviceUUID:deviceUUID, matchOptionals: false, expectedDeletionState:expectedDeletionState)
        
        self.sendDoneUploads(expectedNumberOfUploads: 1, deviceUUID:deviceUUID, masterVersion: uploadRequest.masterVersion + 1)
        
        self.getUploads(expectedFiles: [], deviceUUID:deviceUUID, matchOptionals: false)
        
        let expectedSizes = [
            uploadRequest.fileUUID: fileSize
        ]
        
        self.getFileIndex(expectedFiles: [uploadRequest], masterVersionExpected: uploadRequest.masterVersion + 2, expectedFileSizes: expectedSizes, expectedDeletionState:expectedDeletionState)
    }
    
    func testThatUploadDeletionTwiceOfSameFileWorks() {
        let deviceUUID = PerfectLib.UUID().string
        let (uploadRequest, _) = uploadTextFile(deviceUUID:deviceUUID)
        
        self.sendDoneUploads(expectedNumberOfUploads: 1, deviceUUID:deviceUUID)
        
        let uploadDeletionRequest = UploadDeletionRequest(json: [
            UploadDeletionRequest.fileUUIDKey: uploadRequest.fileUUID,
            UploadDeletionRequest.fileVersionKey: uploadRequest.fileVersion,
            UploadDeletionRequest.masterVersionKey: uploadRequest.masterVersion + 1
        ])!
        
        uploadDeletion(uploadDeletionRequest: uploadDeletionRequest, deviceUUID: deviceUUID, addUser: false)

        uploadDeletion(uploadDeletionRequest: uploadDeletionRequest, deviceUUID: deviceUUID, addUser: false)

        let expectedDeletionState = [
            uploadRequest.fileUUID: true,
        ]
        
        self.getUploads(expectedFiles: [uploadRequest], deviceUUID:deviceUUID, matchOptionals: false, expectedDeletionState:expectedDeletionState)
    }
    
    func testThatUploadDeletionFollowedByDoneUploadsActuallyDeletes() {
        let deviceUUID = PerfectLib.UUID().string
        
        // This file is going to be deleted.
        let (uploadRequest1, fileSize1) = uploadTextFile(deviceUUID:deviceUUID)
        
        self.sendDoneUploads(expectedNumberOfUploads: 1, deviceUUID:deviceUUID)
        
        let uploadDeletionRequest = UploadDeletionRequest(json: [
            UploadDeletionRequest.fileUUIDKey: uploadRequest1.fileUUID,
            UploadDeletionRequest.fileVersionKey: uploadRequest1.fileVersion,
            UploadDeletionRequest.masterVersionKey: uploadRequest1.masterVersion + 1
        ])!
        
        uploadDeletion(uploadDeletionRequest: uploadDeletionRequest, deviceUUID: deviceUUID, addUser: false)
        
        // This file will not be deleted.
        let (uploadRequest2, fileSize2) = uploadTextFile(deviceUUID:deviceUUID, addUser:false, masterVersion: uploadRequest1.masterVersion + 1)

        let expectedDeletionState = [
            uploadRequest1.fileUUID: true,
            uploadRequest2.fileUUID: false
        ]
        
        self.getUploads(expectedFiles: [uploadRequest1, uploadRequest2], deviceUUID:deviceUUID, matchOptionals: false, expectedDeletionState:expectedDeletionState)

        self.sendDoneUploads(expectedNumberOfUploads: 2, deviceUUID:deviceUUID, masterVersion: uploadRequest1.masterVersion + 1)
        
        self.getUploads(expectedFiles: [], deviceUUID:deviceUUID, matchOptionals: false, expectedDeletionState:expectedDeletionState)
        
        let expectedSizes = [
            uploadRequest1.fileUUID: fileSize1,
            uploadRequest2.fileUUID: fileSize2,
        ]

        self.getFileIndex(expectedFiles: [uploadRequest1, uploadRequest2], masterVersionExpected: uploadRequest1.masterVersion + 2, expectedFileSizes: expectedSizes, expectedDeletionState:expectedDeletionState)
    }
    
    // TODO: *0* Test upload deletion with with 2 files

    func testThatDeletionOfDifferentVersionFails() {
        let deviceUUID = PerfectLib.UUID().string
        
        let (uploadRequest1, _) = uploadTextFile(deviceUUID:deviceUUID)
        
        self.sendDoneUploads(expectedNumberOfUploads: 1, deviceUUID:deviceUUID)
        
        let uploadDeletionRequest = UploadDeletionRequest(json: [
            UploadDeletionRequest.fileUUIDKey: uploadRequest1.fileUUID,
            UploadDeletionRequest.fileVersionKey: uploadRequest1.fileVersion + 1,
            UploadDeletionRequest.masterVersionKey: uploadRequest1.masterVersion + 1
        ])!
        
        uploadDeletion(uploadDeletionRequest: uploadDeletionRequest, deviceUUID: deviceUUID, addUser: false, expectError: true)
    }
    
    func testThatDeletionOfUnknownFileUUIDFails() {
        let deviceUUID = PerfectLib.UUID().string
        
        let (uploadRequest1, _) = uploadTextFile(deviceUUID:deviceUUID)
        
        self.sendDoneUploads(expectedNumberOfUploads: 1, deviceUUID:deviceUUID)
        
        let uploadDeletionRequest = UploadDeletionRequest(json: [
            UploadDeletionRequest.fileUUIDKey: PerfectLib.UUID().string,
            UploadDeletionRequest.fileVersionKey: uploadRequest1.fileVersion,
            UploadDeletionRequest.masterVersionKey: uploadRequest1.masterVersion + 1
        ])!
        
        uploadDeletion(uploadDeletionRequest: uploadDeletionRequest, deviceUUID: deviceUUID, addUser: false, expectError: true)
    }
    
    // TODO: *1* Make sure a deviceUUID from a different user cannot do an UploadDeletion for our file.
    
    func testThatDeletionFailsWhenMasterVersionDoesNotMatch() {
        let deviceUUID = PerfectLib.UUID().string
        
        let (uploadRequest1, _) = uploadTextFile(deviceUUID:deviceUUID)
        
        self.sendDoneUploads(expectedNumberOfUploads: 1, deviceUUID:deviceUUID)
        
        let uploadDeletionRequest = UploadDeletionRequest(json: [
            UploadDeletionRequest.fileUUIDKey: uploadRequest1.fileUUID,
            UploadDeletionRequest.fileVersionKey: uploadRequest1.fileVersion,
            UploadDeletionRequest.masterVersionKey: MasterVersionInt(100)
        ])!
        
        uploadDeletion(uploadDeletionRequest: uploadDeletionRequest, deviceUUID: deviceUUID, addUser: false, updatedMasterVersionExpected: 1)
    }
    
    func testThatDebugDeletionFromServerWorks() {
        let deviceUUID = PerfectLib.UUID().string
        
        let (uploadRequest1, _) = uploadTextFile(deviceUUID:deviceUUID)
        
        self.sendDoneUploads(expectedNumberOfUploads: 1, deviceUUID:deviceUUID)
        
        let uploadDeletionRequest = UploadDeletionRequest(json: [
            UploadDeletionRequest.fileUUIDKey: uploadRequest1.fileUUID,
            UploadDeletionRequest.fileVersionKey: uploadRequest1.fileVersion,
            UploadDeletionRequest.masterVersionKey: uploadRequest1.masterVersion + 1,
            UploadDeletionRequest.actualDeletionKey: Int32(1)
        ])!
        
        uploadDeletion(uploadDeletionRequest: uploadDeletionRequest, deviceUUID: deviceUUID, addUser: false)
        
        // Make sure deletion actually occurred!
        
        self.getFileIndex(expectedFiles: [], masterVersionExpected: uploadRequest1.masterVersion + 1, expectedFileSizes: [:], expectedDeletionState:[:])
        
        self.performServerTest { expectation, googleCreds in
            let cloudFileName = uploadDeletionRequest.cloudFileName(deviceUUID: deviceUUID)
            
            googleCreds.searchFor(cloudFileName: cloudFileName, inCloudFolder: uploadRequest1.cloudFolderName, fileMimeType: uploadRequest1.mimeType) { (cloudFileId, error) in
                XCTAssert(error != nil)
                
                guard case GoogleCreds.SearchForFileError.cloudFileDoesNotExist(_) = error as! GoogleCreds.SearchForFileError else {
                    XCTFail()
                    return
                }
                
                XCTAssert(cloudFileId == nil)
                expectation.fulfill()
            }
        }
    }
    
    // Until today, 3/31/17, I had a bug in the server where this didn't work. It would try to delete the file using a name given by the the deviceUUID of the deleting device, not the uploading device.
    func testThatUploadByOneDeviceAndDeletionByAnotherActuallyDeletes() {
        let deviceUUID1 = PerfectLib.UUID().string
        
        // This file is going to be deleted.
        let (uploadRequest1, fileSize1) = uploadTextFile(deviceUUID:deviceUUID1)
        
        self.sendDoneUploads(expectedNumberOfUploads: 1, deviceUUID:deviceUUID1)
        
        let uploadDeletionRequest = UploadDeletionRequest(json: [
            UploadDeletionRequest.fileUUIDKey: uploadRequest1.fileUUID,
            UploadDeletionRequest.fileVersionKey: uploadRequest1.fileVersion,
            UploadDeletionRequest.masterVersionKey: uploadRequest1.masterVersion + 1
        ])!
        
        let deviceUUID2 = PerfectLib.UUID().string

        uploadDeletion(uploadDeletionRequest: uploadDeletionRequest, deviceUUID: deviceUUID2, addUser: false)

        let expectedDeletionState = [
            uploadRequest1.fileUUID: true,
        ]

        self.sendDoneUploads(expectedNumberOfUploads: 1, deviceUUID:deviceUUID2, masterVersion: uploadRequest1.masterVersion + 1)
        
        let expectedSizes = [
            uploadRequest1.fileUUID: fileSize1,
        ]

        self.getFileIndex(expectedFiles: [uploadRequest1], masterVersionExpected: uploadRequest1.masterVersion + 2, expectedFileSizes: expectedSizes, expectedDeletionState:expectedDeletionState)
    }
}

extension FileControllerTests_UploadDeletion {
    static var allTests : [(String, (FileControllerTests_UploadDeletion) -> () throws -> Void)] {
        return [
            ("testThatUploadDeletionTransfersToUploads", testThatUploadDeletionTransfersToUploads),
            ("testThatCombinedUploadDeletionAndFileUploadWork", testThatCombinedUploadDeletionAndFileUploadWork),
            ("testThatUploadDeletionTwiceOfSameFileWorks", testThatUploadDeletionTwiceOfSameFileWorks),
            ("testThatUploadDeletionFollowedByDoneUploadsActuallyDeletes", testThatUploadDeletionFollowedByDoneUploadsActuallyDeletes),
            ("testThatDeletionOfDifferentVersionFails", testThatDeletionOfDifferentVersionFails),
            ("testThatDeletionOfUnknownFileUUIDFails", testThatDeletionOfUnknownFileUUIDFails),
            ("testThatDeletionFailsWhenMasterVersionDoesNotMatch", testThatDeletionFailsWhenMasterVersionDoesNotMatch),
            ("testThatDebugDeletionFromServerWorks", testThatDebugDeletionFromServerWorks),
            ("testThatUploadByOneDeviceAndDeletionByAnotherActuallyDeletes", testThatUploadByOneDeviceAndDeletionByAnotherActuallyDeletes)
        ]
    }
}
