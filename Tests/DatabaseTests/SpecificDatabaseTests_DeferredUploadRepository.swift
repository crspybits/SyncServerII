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

class SpecificDatabaseTests_DeferredUploadRepository: ServerTestCase {
    var repo: DeferredUploadRepository!
    
    override func setUp() {
        super.setUp()
        repo = DeferredUploadRepository(db)
    }
    
    func doAddDeferredUpload(status: DeferredUpload.Status) -> DeferredUpload? {
        let deferredUpload = DeferredUpload()

        deferredUpload.status = status
        
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
        guard let _ = doAddDeferredUpload(status: .pending) else {
            XCTFail()
            return
        }
    }
    
    func testUpdateDeferredUploadWithValidFieldsWorks() {
        guard let deferredUpload = doAddDeferredUpload(status: .pending) else {
            XCTFail()
            return
        }
        
        let newStatus = DeferredUpload.Status.success
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
        default:
            XCTFail()
        }
    }

    func testUpdateDeferredUploadWithNilStatusFails() {
        guard let deferredUpload = doAddDeferredUpload(status: .pending) else {
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
        guard let deferredUpload = doAddDeferredUpload(status: .pending) else {
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
        guard let result = repo.select(rowsWithStatus: .pending) else {
            XCTFail()
            return
        }
        
        XCTAssert(result.count == 0)
    }
    
    func testSelectWithOneRowWorks() {
        guard let _ = doAddDeferredUpload(status: .pending) else {
            XCTFail()
            return
        }
        
        guard let result = repo.select(rowsWithStatus: .pending) else {
            XCTFail()
            return
        }
        
        XCTAssert(result.count == 1)
    }
    
    func testSelectWithTwoRowsWorks() {
        guard let _ = doAddDeferredUpload(status: .pending) else {
            XCTFail()
            return
        }
        
        guard let _ = doAddDeferredUpload(status: .pending) else {
            XCTFail()
            return
        }
        
        guard let result = repo.select(rowsWithStatus: .pending) else {
            XCTFail()
            return
        }
        
        XCTAssert(result.count == 2)
    }
    
    func testSelectWithTwoRowsButOnlyOnePendingWorks() {
        guard let _ = doAddDeferredUpload(status: .pending) else {
            XCTFail()
            return
        }
        
        guard let _ = doAddDeferredUpload(status: .success) else {
            XCTFail()
            return
        }
        
        guard let result = repo.select(rowsWithStatus: .pending) else {
            XCTFail()
            return
        }
        
        XCTAssert(result.count == 1)
    }
}
