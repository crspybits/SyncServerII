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
    
    func uploadDeletion(uploadDeletionRequest:UploadDeletionRequest, deviceUUID:String, addUser:Bool=true, updatedMasterVersionExpected:Int64? = nil, expectError:Bool = false) {
        if addUser {
            self.addNewUser(deviceUUID:deviceUUID)
        }

        self.performServerTest { expectation, googleCreds in
            let headers = self.setupHeaders(accessToken: googleCreds.accessToken, deviceUUID:deviceUUID)
            
            self.performRequest(route: ServerEndpoints.uploadDeletion, headers: headers, urlParameters: "?" + uploadDeletionRequest.urlParameters()!) { response, dict in
                Log.info("Status code: \(response!.statusCode)")
                if expectError {
                    XCTAssert(response!.statusCode != .OK, "Did not fail on upload deletion request")
                }
                else {
                    XCTAssert(response!.statusCode == .OK, "Did not work on upload deletion request")
                    XCTAssert(dict != nil)
                    
                    if let uploadDeletionResponse = UploadDeletionResponse(json: dict!) {
                        if updatedMasterVersionExpected != nil {
                            XCTAssert(uploadDeletionResponse.masterVersionUpdate == updatedMasterVersionExpected)
                        }
                    }
                    else {
                        XCTFail()
                    }
                }
                
                expectation.fulfill()
            }
        }
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
    
    // TODO: *0* Make sure a deviceUUID from a different user cannot do an UploadDeletion for our file.
    
    // TODO: *0* Below:
    func testThatDeletionFailsWhenMasterVersionDoesNotMatch() {
        let deviceUUID = PerfectLib.UUID().string
        
        let (uploadRequest1, _) = uploadTextFile(deviceUUID:deviceUUID)
        
        self.sendDoneUploads(expectedNumberOfUploads: 1, deviceUUID:deviceUUID)
        
        let uploadDeletionRequest = UploadDeletionRequest(json: [
            UploadDeletionRequest.fileUUIDKey: uploadRequest1.fileUUID,
            UploadDeletionRequest.fileVersionKey: uploadRequest1.fileVersion,
            UploadDeletionRequest.masterVersionKey: 100
        ])!
        
        uploadDeletion(uploadDeletionRequest: uploadDeletionRequest, deviceUUID: deviceUUID, addUser: false, updatedMasterVersionExpected: 1)
    }
}
