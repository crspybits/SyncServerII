//
//  MockStorageLiveTests.swift
//  ServerTests
//
//  Created by Christopher G Prince on 6/27/19.
//

import XCTest
@testable import Server
@testable import TestsCommon
import LoggerAPI
import HeliumLogger
import ServerShared

class MockStorageLiveTests: ServerTestCase {
    override func setUp() {
        super.setUp()
        MockStorage.reset()
    }

    func testUploadFile() {
        let deviceUUID = Foundation.UUID().uuidString
        guard let result = uploadTextFile(uploadIndex: 1, uploadCount: 1, deviceUUID:deviceUUID, fileLabel: UUID().uuidString),
            let sharingGroupUUID = result.sharingGroupUUID else {
            XCTFail()
            return
        }
        
        let fileIndexResult = FileIndexRepository(db).fileIndex(forSharingGroupUUID: sharingGroupUUID)
        switch fileIndexResult {
        case .fileIndex(let fileIndex):
            guard fileIndex.count == 1 else {
                XCTFail("fileIndex.count: \(fileIndex.count)")
                return
            }
            
            XCTAssert(fileIndex[0].fileUUID == result.request.fileUUID)
        case .error(_):
            XCTFail()
        }
    }
    
    func testDeleteFile() {
        let deviceUUID = Foundation.UUID().uuidString
        
        // This file is going to be deleted.
        guard let uploadResult1 = uploadTextFile(uploadIndex: 1, uploadCount: 1, deviceUUID:deviceUUID, fileLabel: UUID().uuidString),
            let sharingGroupUUID = uploadResult1.sharingGroupUUID else {
            XCTFail()
            return
        }
        
        let uploadDeletionRequest = UploadDeletionRequest()
        uploadDeletionRequest.fileUUID = uploadResult1.request.fileUUID
        uploadDeletionRequest.sharingGroupUUID = sharingGroupUUID
        
        let result = uploadDeletion(uploadDeletionRequest: uploadDeletionRequest, deviceUUID: deviceUUID, addUser: false)
        XCTAssert(result != nil)
    }
    
    func testDownloadFile() {
        let deviceUUID = Foundation.UUID().uuidString
        
        // This file is going to be deleted.
        guard let uploadResult1 = uploadTextFile(uploadIndex: 1, uploadCount: 1, deviceUUID:deviceUUID, fileLabel: UUID().uuidString),
            let sharingGroupUUID = uploadResult1.sharingGroupUUID else {
            XCTFail()
            return
        }
                
        guard let _ = downloadFile(testAccount: .primaryOwningAccount, fileUUID: uploadResult1.request.fileUUID, fileVersion: 0, sharingGroupUUID: sharingGroupUUID, deviceUUID: deviceUUID) else {
            XCTFail()
            return
        }
    }
}

