//
//  ServerAPI_UploadDeletion.swift
//  SyncServer
//
//  Created by Christopher Prince on 2/19/17.
//  Copyright © 2017 Spastic Muffin, LLC. All rights reserved.
//

import XCTest
@testable import SyncServer
import SMCoreLib

class ServerAPI_UploadDeletion: TestCase {
    
    override func setUp() {
        super.setUp()
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }
    
    override func tearDown() {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
        super.tearDown()
    }

    func testThatUploadDeletionActuallyUploadsTheDeletion() {
        let masterVersion = getMasterVersion()
        
        let fileUUID = UUID().uuidString
        
        guard let (_, file) = uploadFile(fileName: "UploadMe", fileExtension: "txt", mimeType: "text/plain", fileUUID: fileUUID, serverMasterVersion: masterVersion) else {
            return
        }
        
        // for the file upload
        doneUploads(masterVersion: masterVersion, expectedNumberUploads: 1)

        let fileToDelete = ServerAPI.FileToDelete(fileUUID: file.fileUUID, fileVersion: file.fileVersion)
        
        
        let uploadDeletion = self.expectation(description: "getUploads")

        ServerAPI.session.uploadDeletion(file: fileToDelete, serverMasterVersion: masterVersion+1) { (result, error) in
            XCTAssert(error == nil)
            guard case .success = result! else {
                XCTFail()
                return
            }
            uploadDeletion.fulfill()
        }
        
        waitForExpectations(timeout: 10.0, handler: nil)
        
        getUploads(expectedFiles: [
            (fileUUID: fileUUID, fileSize: nil)
        ]) { fileInfo in
            XCTAssert(fileInfo.deleted)
        }
    }
    
    func testThatActualDeletionInDebugWorks() {
        let masterVersion = getMasterVersion()
        
        let fileUUID = UUID().uuidString
        
        guard let (_, file) = uploadFile(fileName: "UploadMe", fileExtension: "txt", mimeType: "text/plain", fileUUID: fileUUID, serverMasterVersion: masterVersion) else {
            return
        }
        
        // for the file upload
        doneUploads(masterVersion: masterVersion, expectedNumberUploads: 1)

        var fileToDelete = ServerAPI.FileToDelete(fileUUID: file.fileUUID, fileVersion: file.fileVersion)
        fileToDelete.actualDeletion = true
        
        let uploadDeletion = self.expectation(description: "uploadDeletion")

        ServerAPI.session.uploadDeletion(file: fileToDelete, serverMasterVersion: masterVersion+1) { (result, error) in
            XCTAssert(error == nil)
            guard case .success = result! else {
                XCTFail()
                return
            }
            uploadDeletion.fulfill()
        }
        
        waitForExpectations(timeout: 10.0, handler: nil)
        
        getFileIndex(expectedFiles: []) { fileInfo in
            XCTAssert(fileInfo.fileUUID != fileUUID)
        }
    }
    
    func testDeleteAllServerFiles() {
        let masterVersion = getMasterVersion()
        
        let fileUUID1 = UUID().uuidString
        let fileUUID2 = UUID().uuidString

        guard let (_, _) = uploadFile(fileName: "UploadMe", fileExtension: "txt", mimeType: "text/plain", fileUUID: fileUUID1, serverMasterVersion: masterVersion) else {
            return
        }
        
        guard let (_, _) = uploadFile(fileName: "UploadMe", fileExtension: "txt", mimeType: "text/plain", fileUUID: fileUUID2, serverMasterVersion: masterVersion) else {
            return
        }
        
        // for the file upload
        doneUploads(masterVersion: masterVersion, expectedNumberUploads: 2)
        
        removeAllServerFiles()
        
        getFileIndex(expectedFiles: []) { fileInfo in
            XCTFail()
        }
    }
}
