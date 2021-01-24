//
//  SpecificDatabaseTests_DeferredUploadRepository.swift
//  Server
//
//  Created by Christopher Prince on 7/11/20
//
//

import XCTest
@testable import Server
@testable import TestsCommon
import LoggerAPI
import HeliumLogger
import Foundation
import ServerShared

class SpecificDatabaseTests_DeferredUploadRepository: ServerTestCase {
    var repo: DeferredUploadRepository!
    
    override func setUp() {
        super.setUp()
        repo = DeferredUploadRepository(db)
    }
    
    func doAddDeferredUpload(userId: UserId, status: DeferredUploadStatus, sharingGroupUUID: String, fileGroupUUID: String? = nil) -> DeferredUpload? {
        let deferredUpload = DeferredUpload()

        deferredUpload.status = status
        deferredUpload.fileGroupUUID = fileGroupUUID
        deferredUpload.sharingGroupUUID = sharingGroupUUID
        deferredUpload.userId = userId
        
        let result = repo.add(deferredUpload)
        
        var deferredUploadId:Int64?
        switch result {
        case .success(deferredUploadId: let id):
            deferredUploadId = id
        
        default:
            return nil
        }
        
        deferredUpload.deferredUploadId = deferredUploadId
        
        return deferredUpload
    }
    
    func testAddDeferredUploadWorks() {
        guard let _ = doAddDeferredUpload(userId: 1, status: .pendingChange, sharingGroupUUID: Foundation.UUID().uuidString) else {
            XCTFail()
            return
        }
    }
    
    func testUpdateDeferredUploadWithValidFieldsWorks() {
        let fileGroupUUID = Foundation.UUID().uuidString
        let sharingGroupUUID = Foundation.UUID().uuidString
        
        guard let deferredUpload = doAddDeferredUpload(userId: 1, status: .pendingChange, sharingGroupUUID: sharingGroupUUID, fileGroupUUID: fileGroupUUID) else {
            XCTFail()
            return
        }
                
        let newStatus = DeferredUploadStatus.completed
        deferredUpload.status = newStatus
        
        guard repo.update(deferredUpload) else {
            XCTFail()
            return
        }
        
        guard let id = deferredUpload.deferredUploadId else {
            XCTFail()
            return
        }
        
        let key = DeferredUploadRepository.LookupKey.deferredUploadId(id)
        let result = repo.lookup(key: key, modelInit: DeferredUpload.init)
        switch result {
        case .found(let model):
            guard let model = model as? DeferredUpload else {
                XCTFail()
                return
            }
            
            XCTAssert(model.deferredUploadId == id)
            XCTAssert(model.status == newStatus)
            XCTAssert(model.fileGroupUUID == fileGroupUUID)
            XCTAssert(model.sharingGroupUUID == sharingGroupUUID)
        default:
            XCTFail()
        }
    }

    func testUpdateDeferredUploadWithNilStatusFails() {
        let sharingGroupUUID = Foundation.UUID().uuidString
        guard let deferredUpload = doAddDeferredUpload(userId: 1, status: .pendingChange, sharingGroupUUID: sharingGroupUUID) else {
            XCTFail()
            return
        }
        
        deferredUpload.status = nil
        
        guard !repo.update(deferredUpload) else {
            XCTFail()
            return
        }
    }
    
    func testUpdateDeferredUploadWithNilIdFails() {
        let sharingGroupUUID = Foundation.UUID().uuidString
        guard let deferredUpload = doAddDeferredUpload(userId: 1, status: .pendingChange, sharingGroupUUID: sharingGroupUUID) else {
            XCTFail()
            return
        }
        
        deferredUpload.deferredUploadId = nil
        
        guard !repo.update(deferredUpload) else {
            XCTFail()
            return
        }
    }
    
    func testSelectWithNoRowsWorks() {
        guard let result = repo.select(rowsWithStatus: [.pendingChange]) else {
            XCTFail()
            return
        }
        
        XCTAssert(result.count == 0)
    }
    
    func testSelectWithOneRowWorks() {
        let sharingGroupUUID = Foundation.UUID().uuidString
        guard let _ = doAddDeferredUpload(userId: 1, status: .pendingChange, sharingGroupUUID: sharingGroupUUID) else {
            XCTFail()
            return
        }
        
        guard let result = repo.select(rowsWithStatus: [.pendingChange]) else {
            XCTFail()
            return
        }
        
        XCTAssert(result.count == 1)
    }
    
    func testSelectWithTwoRowsWorks() {
        let sharingGroupUUID = Foundation.UUID().uuidString
        guard let _ = doAddDeferredUpload(userId: 1, status: .pendingChange, sharingGroupUUID: sharingGroupUUID) else {
            XCTFail()
            return
        }
        
        guard let _ = doAddDeferredUpload(userId: 1, status: .pendingChange, sharingGroupUUID: sharingGroupUUID) else {
            XCTFail()
            return
        }
        
        guard let result = repo.select(rowsWithStatus: [.pendingChange]) else {
            XCTFail()
            return
        }
        
        XCTAssert(result.count == 2)
    }
    
    func testSelectWithTwoRowsButOnlyOnePendingWorks() {
        let sharingGroupUUID = Foundation.UUID().uuidString
        guard let _ = doAddDeferredUpload(userId: 1, status: .pendingChange, sharingGroupUUID: sharingGroupUUID) else {
            XCTFail()
            return
        }
        
        guard let _ = doAddDeferredUpload(userId: 1, status: .completed, sharingGroupUUID: sharingGroupUUID) else {
            XCTFail()
            return
        }
        
        guard let result = repo.select(rowsWithStatus: [.pendingChange]) else {
            XCTFail()
            return
        }
        
        XCTAssert(result.count == 1)
    }
}
