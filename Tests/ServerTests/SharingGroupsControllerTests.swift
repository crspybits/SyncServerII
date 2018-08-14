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
    
    // MARK: Remove user from sharing group
    
    func testRemoveUserFromSharingGroup_lastUserInSharingGroup() {
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
        
        guard removeUserFromSharingGroup(deviceUUID: deviceUUID, sharingGroupId: sharingGroupId, masterVersion: masterVersion) else {
            XCTFail()
            return
        }
        
        let key1 = SharingGroupRepository.LookupKey.sharingGroupId(sharingGroupId)
        let result1 = SharingGroupRepository(db).lookup(key: key1, modelInit: SharingGroup.init)
        guard case .found(let model) = result1, let sharingGroup = model as? Server.SharingGroup else {
            XCTFail()
            return
        }
        
        guard sharingGroup.deleted else {
            XCTFail()
            return
        }
        
        let key2 = SharingGroupUserRepository.LookupKey.userId(addUserResponse.userId)
        let result2 = SharingGroupUserRepository(db).lookup(key: key2 , modelInit: SharingGroupUser.init)
        guard case .noObjectFound = result2 else {
            XCTFail()
            return
        }
    }
    
    func testRemoveUserFromSharingGroup_notLastUserInSharingGroup() {
        let deviceUUID = Foundation.UUID().uuidString
        guard let addUserResponse = self.addNewUser(deviceUUID:deviceUUID),
            let sharingGroupId = addUserResponse.sharingGroupId else {
            XCTFail()
            return
        }

        var sharingInvitationUUID:String!
        
        createSharingInvitation(permission: .read, sharingGroupId:sharingGroupId) { expectation, invitationUUID in
            sharingInvitationUUID = invitationUUID
            expectation.fulfill()
        }
        
        let sharingUser: TestAccount = .dropbox1
        
        redeemSharingInvitation(sharingUser:sharingUser, sharingInvitationUUID: sharingInvitationUUID) { result, expectation in
            expectation.fulfill()
        }
        
        guard let masterVersion = getMasterVersion(sharingGroupId: sharingGroupId) else {
            XCTFail()
            return
        }
        
        guard removeUserFromSharingGroup(deviceUUID: deviceUUID, sharingGroupId: sharingGroupId, masterVersion: masterVersion) else {
            XCTFail()
            return
        }
        
        guard let masterVersion2 = getMasterVersion(testAccount: sharingUser, sharingGroupId: sharingGroupId), masterVersion + 1 == masterVersion2 else {
            XCTFail()
            return
        }
        
        let key1 = SharingGroupRepository.LookupKey.sharingGroupId(sharingGroupId)
        let result1 = SharingGroupRepository(db).lookup(key: key1, modelInit: SharingGroup.init)
        guard case .found(let model) = result1, let sharingGroup = model as? Server.SharingGroup else {
            XCTFail()
            return
        }
        
        // Still one user in sharing group-- should not be deleted.
        guard !sharingGroup.deleted else {
            XCTFail()
            return
        }
        
        let key2 = SharingGroupUserRepository.LookupKey.userId(addUserResponse.userId)
        let result2 = SharingGroupUserRepository(db).lookup(key: key2 , modelInit: SharingGroupUser.init)
        guard case .noObjectFound = result2 else {
            XCTFail()
            return
        }
    }
    
    func testRemoveUserFromSharingGroup_failsWithBadMasterVersion() {
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
        
        guard removeUserFromSharingGroup(deviceUUID: deviceUUID, sharingGroupId: sharingGroupId, masterVersion: masterVersion + 1) else {
            XCTFail()
            return
        }
    }
    
    /*
        Test remove user from sharing group
            When user has files in the sharing group-- those should be marked as deleted.
            When owning user has sharing users in sharing group
                Those should no longer be able to upload to the sharing group.
    */
}

extension SharingGroupsControllerTests {
    static var allTests : [(String, (SharingGroupsControllerTests) -> () throws -> Void)] {
        return [
            ("testCreateSharingGroupWorks", testCreateSharingGroupWorks),
            ("testNewlyCreatedSharingGroupHasNoFiles", testNewlyCreatedSharingGroupHasNoFiles),
            ("testUpdateSharingGroupWorks", testUpdateSharingGroupWorks),
            ("testRemoveSharingGroupWorks", testRemoveSharingGroupWorks),
            ("testUpdateSharingGroupForDeletedSharingGroupFails", testUpdateSharingGroupForDeletedSharingGroupFails),
            ("testRemoveUserFromSharingGroup_lastUserInSharingGroup", testRemoveUserFromSharingGroup_lastUserInSharingGroup),
            ("testRemoveUserFromSharingGroup_notLastUserInSharingGroup", testRemoveUserFromSharingGroup_notLastUserInSharingGroup),
            ("testRemoveUserFromSharingGroup_failsWithBadMasterVersion",
                testRemoveUserFromSharingGroup_failsWithBadMasterVersion)
        ]
    }
    
    func testLinuxTestSuiteIncludesAllTests() {
        linuxTestSuiteIncludesAllTests(testType: SharingGroupsControllerTests.self)
    }
}
