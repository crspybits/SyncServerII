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
        uploadDeletion()
    }
    
    func testThatTwoUploadDeletionsOfTheSameFileWork() {
        let masterVersion = getMasterVersion()
        
        let fileUUID = UUID().uuidString
        let fileURL = Bundle(for: ServerAPI_UploadFile.self).url(forResource: "UploadMe", withExtension: "txt")!
        
        guard let (_, file) = uploadFile(fileURL:fileURL, mimeType: "text/plain", fileUUID: fileUUID, serverMasterVersion: masterVersion) else {
            XCTFail()
            return
        }
        
        // for the file upload
        doneUploads(masterVersion: masterVersion, expectedNumberUploads: 1)

        let fileToDelete = ServerAPI.FileToDelete(fileUUID: file.fileUUID, fileVersion: file.fileVersion)
        uploadDeletion(fileToDelete: fileToDelete, masterVersion: masterVersion+1)

        uploadDeletion(fileToDelete: fileToDelete, masterVersion: masterVersion+1)

        getUploads(expectedFiles: [
            (fileUUID: fileUUID, fileSize: nil)
        ]) { fileInfo in
            XCTAssert(fileInfo.deleted)
        }
    }
    
    // TODO: *0* Do an upload deletion, then a second upload deletion with the same file-- make sure the 2nd one fails.
    
    func testThatActualDeletionInDebugWorks() {
        let masterVersion = getMasterVersion()
        
        let fileUUID = UUID().uuidString
        
        let fileURL = Bundle(for: ServerAPI_UploadFile.self).url(forResource: "UploadMe", withExtension: "txt")!
        
        guard let (_, file) = uploadFile(fileURL:fileURL, mimeType: "text/plain", fileUUID: fileUUID, serverMasterVersion: masterVersion) else {
            return
        }
        
        // for the file upload
        doneUploads(masterVersion: masterVersion, expectedNumberUploads: 1)

        var fileToDelete = ServerAPI.FileToDelete(fileUUID: file.fileUUID, fileVersion: file.fileVersion)
        fileToDelete.actualDeletion = true
        uploadDeletion(fileToDelete: fileToDelete, masterVersion: masterVersion+1)
        
        getFileIndex(expectedFiles: []) { fileInfo in
            XCTAssert(fileInfo.fileUUID != fileUUID)
        }
    }
    
    func testDeleteAllServerFiles() {
        let masterVersion = getMasterVersion()
        
        let fileUUID1 = UUID().uuidString
        let fileUUID2 = UUID().uuidString
        let fileURL = Bundle(for: ServerAPI_UploadFile.self).url(forResource: "UploadMe", withExtension: "txt")!
        
        guard let (_, _) = uploadFile(fileURL:fileURL, mimeType: "text/plain", fileUUID: fileUUID1, serverMasterVersion: masterVersion) else {
            return
        }
        
        guard let (_, _) = uploadFile(fileURL:fileURL, mimeType: "text/plain", fileUUID: fileUUID2, serverMasterVersion: masterVersion) else {
            return
        }
        
        // for the file upload
        doneUploads(masterVersion: masterVersion, expectedNumberUploads: 2)
        
        removeAllServerFilesInFileIndex()
        
        getFileIndex(expectedFiles: []) { fileInfo in
            XCTFail()
        }
    }
}
