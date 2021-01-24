//
//  SpecificDatabaseTests_SharingGroupUsers.swift
//  ServerTests
//
//  Created by Christopher G Prince on 7/4/18.
//

import XCTest
@testable import Server
import LoggerAPI
import HeliumLogger
import Foundation
import SyncServerShared

class SpecificDatabaseTests_SharingGroupUsers: ServerTestCase, LinuxTestable {

    override func setUp() {
        super.setUp()
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }
    
    override func tearDown() {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
        super.tearDown()
    }
    
    @discardableResult
    func addSharingGroupUser(sharingGroupUUID: String, userId: UserId, owningUserId: UserId?, failureExpected: Bool = false) -> SharingGroupUserId? {
        let result = SharingGroupUserRepository(db).add(sharingGroupUUID: sharingGroupUUID, userId: userId, permission: .read, owningUserId: owningUserId)
        
        var sharingGroupUserId:SharingGroupUserId?
        switch result {
        case .success(sharingGroupUserId: let id):
            if failureExpected {
                XCTFail()
            }
            else {
                sharingGroupUserId = id
            }
        
        case .error:
            if !failureExpected {
                XCTFail()
            }
        }
        
        return sharingGroupUserId
    }

    func testAddSharingGroupUser() {
        let sharingGroupUUID = UUID().uuidString
        guard addSharingGroup(sharingGroupUUID: sharingGroupUUID) else {
            XCTFail()
            return
        }
        
        let user1 = User()
        user1.username = "Chris"
        user1.accountType = .Google
        user1.creds = "{\"accessToken\": \"SomeAccessTokenValue1\"}"
        user1.credsId = "100"
        
        guard let userId: UserId = UserRepository(db).add(user: user1, validateJSON: false) else {
            XCTFail()
            return
        }
        
        guard let _ = addSharingGroupUser(sharingGroupUUID:sharingGroupUUID, userId: userId, owningUserId: nil) else {
            XCTFail()
            return
        }
    }
    
    func testAddMultipleSharingGroupUsers() {
        let sharingGroupUUID = UUID().uuidString
        guard addSharingGroup(sharingGroupUUID: sharingGroupUUID) else {
            XCTFail()
            return
        }

        let user1 = User()
        user1.username = "Chris"
        user1.accountType = .Google
        user1.creds = "{\"accessToken\": \"SomeAccessTokenValue1\"}"
        user1.credsId = "100"
        
        guard let userId1: UserId = UserRepository(db).add(user: user1, validateJSON: false) else {
            XCTFail()
            return
        }
        
        guard let id1 = addSharingGroupUser(sharingGroupUUID:sharingGroupUUID, userId: userId1, owningUserId: nil) else {
            XCTFail()
            return
        }
        
        let user2 = User()
        user2.username = "Chris"
        user2.accountType = .Google
        user2.creds = "{\"accessToken\": \"SomeAccessTokenValue1\"}"
        user2.credsId = "101"
        
        guard let userId2: UserId = UserRepository(db).add(user: user2, validateJSON: false) else {
            XCTFail()
            return
        }
        
        guard let id2 = addSharingGroupUser(sharingGroupUUID:sharingGroupUUID, userId: userId2, owningUserId: nil) else {
            XCTFail()
            return
        }
        
        XCTAssert(id1 != id2)
    }
    
    func testAddSharingGroupUserFailsIfYouAddTheSameUserToSameGroupTwice() {
        let sharingGroupUUID = UUID().uuidString
        guard addSharingGroup(sharingGroupUUID: sharingGroupUUID) else {
            XCTFail()
            return
        }

        let user1 = User()
        user1.username = "Chris"
        user1.accountType = .Google
        user1.creds = "{\"accessToken\": \"SomeAccessTokenValue1\"}"
        user1.credsId = "100"
        
        guard let userId1: UserId = UserRepository(db).add(user: user1, validateJSON: false) else {
            XCTFail()
            return
        }
        
        guard let _ = addSharingGroupUser(sharingGroupUUID:sharingGroupUUID, userId: userId1, owningUserId: nil) else {
            XCTFail()
            return
        }
        
        addSharingGroupUser(sharingGroupUUID:sharingGroupUUID, userId: userId1, owningUserId: nil, failureExpected: true)
    }
    
    func testLookupFromSharingGroupUser() {
        let sharingGroupUUID = UUID().uuidString
        guard addSharingGroup(sharingGroupUUID: sharingGroupUUID) else {
            XCTFail()
            return
        }

        guard MasterVersionRepository(db).initialize(sharingGroupUUID: sharingGroupUUID) else {
            XCTFail()
            return
        }

        let user1 = User()
        user1.username = "Chris"
        user1.accountType = .Google
        user1.creds = "{\"accessToken\": \"SomeAccessTokenValue1\"}"
        user1.credsId = "100"
        
        guard let userId: UserId = UserRepository(db).add(user: user1, validateJSON: false) else {
            XCTFail()
            return
        }
        
        guard let _ = addSharingGroupUser(sharingGroupUUID:sharingGroupUUID, userId: userId, owningUserId: nil) else {
            XCTFail()
            return
        }
        
        let key = SharingGroupUserRepository.LookupKey.primaryKeys(sharingGroupUUID: sharingGroupUUID, userId: userId)
        let result = SharingGroupUserRepository(db).lookup(key: key, modelInit: SharingGroupUser.init)
        switch result {
        case .found(let model):
            guard let obj = model as? Server.SharingGroupUser else {
                XCTFail()
                return
            }
            XCTAssert(obj.sharingGroupUUID == sharingGroupUUID)
            XCTAssert(obj.userId == userId)
            XCTAssert(obj.sharingGroupUserId != nil)
        case .noObjectFound:
            XCTFail("No object found")
        case .error(let error):
            XCTFail("Error: \(error)")
        }
        
        guard let groups = SharingGroupRepository(db).sharingGroups(forUserId: userId, sharingGroupUserRepo: SharingGroupUserRepository(db), userRepo: UserRepository(db)), groups.count == 1 else {
            XCTFail()
            return
        }
        
        XCTAssert(groups[0].sharingGroupUUID == sharingGroupUUID)
    }

    func testGetUserSharingGroupsForMultipleGroups() {
        let sharingGroupUUID1 = UUID().uuidString

        guard addSharingGroup(sharingGroupUUID: sharingGroupUUID1) else {
            XCTFail()
            return
        }
        
        guard MasterVersionRepository(db).initialize(sharingGroupUUID: sharingGroupUUID1) else {
            XCTFail()
            return
        }

        let sharingGroupUUID2 = UUID().uuidString

        guard addSharingGroup(sharingGroupUUID: sharingGroupUUID2, sharingGroupName: "Foobar") else {
            XCTFail()
            return
        }
        
        guard MasterVersionRepository(db).initialize(sharingGroupUUID: sharingGroupUUID2) else {
            XCTFail()
            return
        }

        let user1 = User()
        user1.username = "Chris"
        user1.accountType = .Google
        user1.creds = "{\"accessToken\": \"SomeAccessTokenValue1\"}"
        user1.credsId = "100"
        
        guard let userId: UserId = UserRepository(db).add(user: user1, validateJSON: false) else {
            XCTFail()
            return
        }
        
        guard let _ = addSharingGroupUser(sharingGroupUUID:sharingGroupUUID1, userId: userId, owningUserId: nil) else {
            XCTFail()
            return
        }
        
        guard let _ = addSharingGroupUser(sharingGroupUUID:sharingGroupUUID2, userId: userId, owningUserId: nil) else {
            XCTFail()
            return
        }
        
        guard let groups = SharingGroupRepository(db).sharingGroups(forUserId: userId, sharingGroupUserRepo: SharingGroupUserRepository(db), userRepo: UserRepository(db)), groups.count == 2 else {
            XCTFail()
            return
        }
        
        let filter1 = groups.filter {$0.sharingGroupUUID == sharingGroupUUID1}
        guard filter1.count == 1 else {
            XCTFail()
            return
        }
        
        XCTAssert(filter1[0].sharingGroupName == nil)
        
        let filter2 = groups.filter {$0.sharingGroupUUID == sharingGroupUUID2}
        guard filter2.count == 1 else {
            XCTFail()
            return
        }
        XCTAssert(filter2[0].sharingGroupName == "Foobar")
    }
}

extension SpecificDatabaseTests_SharingGroupUsers {
    static var allTests : [(String, (SpecificDatabaseTests_SharingGroupUsers) -> () throws -> Void)] {
        return [
            ("testAddSharingGroupUser", testAddSharingGroupUser),
            ("testAddMultipleSharingGroupUsers", testAddMultipleSharingGroupUsers),
            ("testAddSharingGroupUserFailsIfYouAddTheSameUserToSameGroupTwice", testAddSharingGroupUserFailsIfYouAddTheSameUserToSameGroupTwice),
            ("testLookupFromSharingGroupUser", testLookupFromSharingGroupUser),
            ("testGetUserSharingGroupsForMultipleGroups", testGetUserSharingGroupsForMultipleGroups)
        ]
    }
    
    func testLinuxTestSuiteIncludesAllTests() {
        linuxTestSuiteIncludesAllTests(testType: SpecificDatabaseTests_SharingGroupUsers.self)
    }
}
