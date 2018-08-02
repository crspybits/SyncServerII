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
    func addSharingGroupUser(sharingGroupId: SharingGroupId, userId: UserId, failureExpected: Bool = false) -> SharingGroupUserId? {
        let result = SharingGroupUserRepository(db).add(sharingGroupId: sharingGroupId, userId: userId)
        
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
        guard let sharingGroupId = addSharingGroup() else {
            XCTFail()
            return
        }
        
        let user1 = User()
        user1.username = "Chris"
        user1.accountType = .Google
        user1.creds = "{\"accessToken\": \"SomeAccessTokenValue1\"}"
        user1.credsId = "100"
        user1.permission = .admin
        
        guard let userId: UserId = UserRepository(db).add(user: user1) else {
            XCTFail()
            return
        }
        
        guard let _ = addSharingGroupUser(sharingGroupId:sharingGroupId, userId: userId) else {
            XCTFail()
            return
        }
    }
    
    func testAddMultipleSharingGroupUsers() {
        guard let sharingGroupId = addSharingGroup() else {
            XCTFail()
            return
        }

        let user1 = User()
        user1.username = "Chris"
        user1.accountType = .Google
        user1.creds = "{\"accessToken\": \"SomeAccessTokenValue1\"}"
        user1.credsId = "100"
        user1.permission = .admin
        
        guard let userId1: UserId = UserRepository(db).add(user: user1) else {
            XCTFail()
            return
        }
        
        guard let id1 = addSharingGroupUser(sharingGroupId:sharingGroupId, userId: userId1) else {
            XCTFail()
            return
        }
        
        let user2 = User()
        user2.username = "Chris"
        user2.accountType = .Google
        user2.creds = "{\"accessToken\": \"SomeAccessTokenValue1\"}"
        user2.credsId = "101"
        user2.permission = .admin
        
        guard let userId2: UserId = UserRepository(db).add(user: user2) else {
            XCTFail()
            return
        }
        
        guard let id2 = addSharingGroupUser(sharingGroupId:sharingGroupId, userId: userId2) else {
            XCTFail()
            return
        }
        
        XCTAssert(id1 != id2)
    }
    
    func testAddSharingGroupUserFailsIfYouAddTheSameUserToSameGroupTwice() {
        guard let sharingGroupId = addSharingGroup() else {
            XCTFail()
            return
        }

        let user1 = User()
        user1.username = "Chris"
        user1.accountType = .Google
        user1.creds = "{\"accessToken\": \"SomeAccessTokenValue1\"}"
        user1.credsId = "100"
        user1.permission = .admin
        
        guard let userId1: UserId = UserRepository(db).add(user: user1) else {
            XCTFail()
            return
        }
        
        guard let _ = addSharingGroupUser(sharingGroupId:sharingGroupId, userId: userId1) else {
            XCTFail()
            return
        }
        
        addSharingGroupUser(sharingGroupId:sharingGroupId, userId: userId1, failureExpected: true)
    }
    
    func testLookupFromSharingGroupUser() {
        guard let sharingGroupId = addSharingGroup() else {
            XCTFail()
            return
        }

        let user1 = User()
        user1.username = "Chris"
        user1.accountType = .Google
        user1.creds = "{\"accessToken\": \"SomeAccessTokenValue1\"}"
        user1.credsId = "100"
        user1.permission = .admin
        
        guard let userId: UserId = UserRepository(db).add(user: user1) else {
            XCTFail()
            return
        }
        
        guard let _ = addSharingGroupUser(sharingGroupId:sharingGroupId, userId: userId) else {
            XCTFail()
            return
        }
        
        let key = SharingGroupUserRepository.LookupKey.primaryKeys(sharingGroupId: sharingGroupId, userId: userId)
        let result = SharingGroupUserRepository(db).lookup(key: key, modelInit: SharingGroupUser.init)
        switch result {
        case .found(let model):
            guard let obj = model as? SharingGroupUser else {
                XCTFail()
                return
            }
            XCTAssert(obj.sharingGroupId == sharingGroupId)
            XCTAssert(obj.userId == userId)
            XCTAssert(obj.sharingGroupUserId != nil)
        case .noObjectFound:
            XCTFail("No object found")
        case .error(let error):
            XCTFail("Error: \(error)")
        }
        
        guard let groups = SharingGroupRepository(db).sharingGroups(forUserId: userId), groups.count == 1 else {
            XCTFail()
            return
        }
        
        XCTAssert(groups[0].sharingGroupId == sharingGroupId)
    }

    func testGetUserSharingGroupsForMultipleGroups() {
        guard let sharingGroupId1 = addSharingGroup() else {
            XCTFail()
            return
        }

        guard let sharingGroupId2 = addSharingGroup(sharingGroupName: "Foobar") else {
            XCTFail()
            return
        }

        let user1 = User()
        user1.username = "Chris"
        user1.accountType = .Google
        user1.creds = "{\"accessToken\": \"SomeAccessTokenValue1\"}"
        user1.credsId = "100"
        user1.permission = .admin
        
        guard let userId: UserId = UserRepository(db).add(user: user1) else {
            XCTFail()
            return
        }
        
        guard let _ = addSharingGroupUser(sharingGroupId:sharingGroupId1, userId: userId) else {
            XCTFail()
            return
        }
        
        guard let _ = addSharingGroupUser(sharingGroupId:sharingGroupId2, userId: userId) else {
            XCTFail()
            return
        }
        
        guard let groups = SharingGroupRepository(db).sharingGroups(forUserId: userId), groups.count == 2 else {
            XCTFail()
            return
        }
        
        XCTAssert(groups[0].sharingGroupId == sharingGroupId1)
        XCTAssert(groups[0].sharingGroupName == nil)
        XCTAssert(groups[1].sharingGroupId == sharingGroupId2)
        XCTAssert(groups[1].sharingGroupName == "Foobar")
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
