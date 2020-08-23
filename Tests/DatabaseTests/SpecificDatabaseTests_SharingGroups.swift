//
//  SpecificDatabaseTests_SharingGroups.swift
//  ServerTests
//
//  Created by Christopher G Prince on 7/4/18.
//

import XCTest
@testable import Server
@testable import TestsCommon
import LoggerAPI
import HeliumLogger
import Foundation
import ServerShared

class SpecificDatabaseTests_SharingGroups: ServerTestCase {

    override func setUp() {
        super.setUp()
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }
    
    override func tearDown() {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
        super.tearDown()
    }

    func testAddSharingGroupWithoutName() {
        let sharingGroupUUID = UUID().uuidString
        guard addSharingGroup(sharingGroupUUID: sharingGroupUUID) else {
            XCTFail()
            return
        }
    }
    
    func testAddSharingGroupWithName() {
        let sharingGroupUUID = UUID().uuidString
        guard addSharingGroup(sharingGroupUUID: sharingGroupUUID, sharingGroupName: "Foobar") else {
            XCTFail()
            return
        }
    }
    
    func testLookupFromSharingGroupExisting() {
        let sharingGroupUUID = UUID().uuidString
        guard addSharingGroup(sharingGroupUUID: sharingGroupUUID) else {
            XCTFail()
            return
        }
        
        let key = SharingGroupRepository.LookupKey.sharingGroupUUID(sharingGroupUUID)
        let result = SharingGroupRepository(db).lookup(key: key, modelInit: SharingGroup.init)
        switch result {
        case .found(let model):
            guard let obj = model as? Server.SharingGroup else {
                XCTFail()
                return
            }
            XCTAssert(obj.sharingGroupUUID != nil)
        case .noObjectFound:
            XCTFail("No object found")
        case .error(let error):
            XCTFail("Error: \(error)")
        }
    }

    func testLookupFromSharingGroupNonExisting() {
        let key = SharingGroupRepository.LookupKey.sharingGroupUUID(UUID().uuidString)
        let result = SharingGroupRepository(db).lookup(key: key, modelInit: SharingGroup.init)
        switch result {
        case .found:
            XCTFail()
        case .noObjectFound:
            break
        case .error(let error):
            XCTFail("Error: \(error)")
        }
    }
}
