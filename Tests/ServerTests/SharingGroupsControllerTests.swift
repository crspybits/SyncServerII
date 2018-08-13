//
//  SharingGroupsControllerTests.swift
//  ServerTests
//
//  Created by Christopher G Prince on 7/15/18.
//

import XCTest
@testable import Server
import LoggerAPI
import Foundation
import SyncServerShared

class SharingGroupsControllerTests: ServerTestCase, LinuxTestable {
    override func setUp() {
        super.setUp()
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }
    
    override func tearDown() {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
        super.tearDown()
    }
    
    func testCreateSharingGroupWorks() {
        let deviceUUID = Foundation.UUID().uuidString
        guard let _ = self.addNewUser(deviceUUID:deviceUUID) else {
            XCTFail()
            return
        }
        
        let sharingGroup = SyncServerShared.SharingGroup()!
        sharingGroup.sharingGroupName = "Louisiana Guys"
        
        guard let sharingGroupId2 = createSharingGroup(deviceUUID:deviceUUID, sharingGroup: sharingGroup) else {
            XCTFail()
            return
        }
        
        guard let (_, sharingGroups) = getIndex() else {
            XCTFail()
            return
        }
        
        let filtered = sharingGroups.filter {$0.sharingGroupId == sharingGroupId2}
        guard filtered.count == 1 else {
            XCTFail()
            return
        }
        
        XCTAssert(filtered[0].sharingGroupName == sharingGroup.sharingGroupName)
    }
    
    func testNewlyCreatedSharingGroupHasNoFiles() {
        let deviceUUID = Foundation.UUID().uuidString
        guard let _ = self.addNewUser(deviceUUID:deviceUUID) else {
            XCTFail()
            return
        }
        
        let sharingGroup = SyncServerShared.SharingGroup()!
        sharingGroup.sharingGroupName = "Louisiana Guys"
        
        guard let sharingGroupId = createSharingGroup(deviceUUID:deviceUUID, sharingGroup: sharingGroup) else {
            XCTFail()
            return
        }
        
        guard let (files, sharingGroups) = getIndex(sharingGroupId: sharingGroupId) else {
            XCTFail()
            return
        }
        
        guard files != nil && files?.count == 0 else {
            XCTFail()
            return
        }
        
        guard sharingGroups.count == 2 else {
            XCTFail()
            return
        }
    }
    
    func testUpdateSharingGroupWorks() {
        let deviceUUID = Foundation.UUID().uuidString
        guard let addUserResponse = self.addNewUser(deviceUUID:deviceUUID),
            let sharingGroupId = addUserResponse.sharingGroupId else {
            XCTFail()
            return
        }
        
        guard let masterVersion = getMasterVersion(sharingGroupId: sharingGroupId) else {
            XCTFail()
            return
        }
        
        let sharingGroup = SyncServerShared.SharingGroup()!
        sharingGroup.sharingGroupId = sharingGroupId
        sharingGroup.sharingGroupName = "Louisiana Guys"
        
        guard updateSharingGroup(deviceUUID:deviceUUID, sharingGroup: sharingGroup, masterVersion: masterVersion) else {
            XCTFail()
            return
        }
    }
    
    func testRemoveSharingGroupWorks() {
        let deviceUUID = Foundation.UUID().uuidString
        guard let addUserResponse = self.addNewUser(deviceUUID:deviceUUID),
            let sharingGroupId = addUserResponse.sharingGroupId else {
            XCTFail()
            return
        }
        
        guard let masterVersion = getMasterVersion(sharingGroupId: sharingGroupId) else {
            XCTFail()
            return
        }
        
        guard removeSharingGroup(deviceUUID:deviceUUID, sharingGroupId: sharingGroupId, masterVersion: masterVersion) else {
            XCTFail()
            return
        }
    }

    func testUpdateSharingGroupForDeletedSharingGroupFails() {
        let deviceUUID = Foundation.UUID().uuidString
        guard let addUserResponse = self.addNewUser(deviceUUID:deviceUUID),
            let sharingGroupId = addUserResponse.sharingGroupId else {
            XCTFail()
            return
        }
        
        guard var masterVersion = getMasterVersion(sharingGroupId: sharingGroupId) else {
            XCTFail()
            return
        }
        
        guard removeSharingGroup(deviceUUID:deviceUUID, sharingGroupId: sharingGroupId, masterVersion: masterVersion) else {
            XCTFail()
            return
        }
        
        masterVersion += 1
        
        let sharingGroup = SyncServerShared.SharingGroup()!
        sharingGroup.sharingGroupId = sharingGroupId
        sharingGroup.sharingGroupName = "Louisiana Guys"
        
        let result = updateSharingGroup(deviceUUID:deviceUUID, sharingGroup: sharingGroup, masterVersion: masterVersion, expectFailure: true)
        XCTAssert(result == false)
    }
}

extension SharingGroupsControllerTests {
    static var allTests : [(String, (SharingGroupsControllerTests) -> () throws -> Void)] {
        return [
            ("testCreateSharingGroupWorks", testCreateSharingGroupWorks),
            ("testNewlyCreatedSharingGroupHasNoFiles", testNewlyCreatedSharingGroupHasNoFiles),
            ("testUpdateSharingGroupWorks", testUpdateSharingGroupWorks),
            ("testRemoveSharingGroupWorks", testRemoveSharingGroupWorks),
            ("testUpdateSharingGroupForDeletedSharingGroupFails", testUpdateSharingGroupForDeletedSharingGroupFails)
        ]
    }
    
    func testLinuxTestSuiteIncludesAllTests() {
        linuxTestSuiteIncludesAllTests(testType: SharingGroupsControllerTests.self)
    }
}
