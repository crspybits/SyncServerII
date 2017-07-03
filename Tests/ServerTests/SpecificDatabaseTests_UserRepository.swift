//
//  SpecificDatabaseTests_UserRepository.swift
//  Server
//
//  Created by Christopher Prince on 4/11/17.
//
//

import XCTest
@testable import Server
import LoggerAPI
import HeliumLogger
import Credentials
import CredentialsGoogle
import PerfectLib
import Foundation

class SpecificDatabaseTests_UserRepository: ServerTestCase {

    override func setUp() {
        super.setUp()
    }
    
    func addOwningUsers() {
        let user1 = User()
        user1.username = "Chris"
        user1.accountType = .Google
        user1.creds = "{\"accessToken\": \"SomeAccessTokenValue1\"}"
        user1.credsId = "100"
        user1.userType = .owning
        
        let result1 = UserRepository(db).add(user: user1)
        XCTAssert(result1 == 1, "Bad credentialsId!")

        let user2 = User()
        user2.username = "Natasha"
        user2.accountType = .Google
        user2.creds = "{\"accessToken\": \"SomeAccessTokenValue2\"}"
        user2.credsId = "200"
        user2.userType = .owning

        let result2 = UserRepository(db).add(user: user2)
        XCTAssert(result2 == 2, "Bad credentialsId!")
    }
    
    func testAddOwningUser() {
        addOwningUsers()
    }
    
    func testAddOwningUserFailsIfYouGiveAnOwningUserId() {
        let user1 = User()
        user1.username = "Chris"
        user1.accountType = .Google
        user1.creds = "{\"accessToken\": \"SomeAccessTokenValue1\"}"
        user1.credsId = "100"
        user1.userType = .owning
        user1.owningUserId = 100
        
        let result1 = UserRepository(db).add(user: user1)
        XCTAssert(result1 == nil, "Good id!!")
    }
    
    func testAddOwningUserFailsIfYouGivePermissions() {
        let user1 = User()
        user1.username = "Chris"
        user1.accountType = .Google
        user1.creds = "{\"accessToken\": \"SomeAccessTokenValue1\"}"
        user1.credsId = "100"
        user1.userType = .owning
        user1.sharingPermission = .admin
        
        let result1 = UserRepository(db).add(user: user1)
        XCTAssert(result1 == nil, "Good id!!")
    }
    
    func addSharingUser() {
        let user1 = User()
        user1.username = "Chris"
        user1.accountType = .Google
        user1.creds = "{\"accessToken\": \"SomeAccessTokenValue1\"}"
        user1.credsId = "100"
        user1.userType = .sharing
        user1.sharingPermission = .write
        user1.owningUserId = 100

        let result1 = UserRepository(db).add(user: user1)
        XCTAssert(result1 == 1, "Bad credentialsId!")
    }
    
    func testAddSharingUser() {
        addSharingUser()
    }
    
    func testUserLookup1() {
        addOwningUsers()
        
        let result = UserRepository(db).lookup(key: .userId(1), modelInit:User.init)
        switch result {
        case .error(let error):
            XCTFail("\(error)")
            
        case .found(let object):
            let user = object as! User
            XCTAssert(user.accountType == .Google)
            XCTAssert(user.username == "Chris")
            XCTAssert(user.creds == "{\"accessToken\": \"SomeAccessTokenValue1\"}")
            XCTAssert(user.userId == 1)
            
        case .noObjectFound:
            XCTFail("No User Found")
        }
    }
    
    func testUserLookup1b() {
        addOwningUsers()
        
        let result = UserRepository(db).lookup(key: .userId(1), modelInit: User.init)
        switch result {
        case .error(let error):
            XCTFail("\(error)")
            
        case .found(let object):
            let user = object as! User
            XCTAssert(user.accountType == .Google)
            XCTAssert(user.username == "Chris")
            XCTAssert(user.creds == "{\"accessToken\": \"SomeAccessTokenValue1\"}")
            XCTAssert(user.userId == 1)
            
        case .noObjectFound:
            XCTFail("No User Found")
        }
    }
    
    func testUserLookup2() {
        addOwningUsers()
        
        let result = UserRepository(db).lookup(key: .accountTypeInfo(accountType:.Google, credsId:"100"), modelInit:User.init)
        switch result {
        case .error(let error):
            XCTFail("\(error)")
            
        case .found(let object):
            let user = object as! User
            XCTAssert(user.accountType == .Google)
            XCTAssert(user.username == "Chris")
            XCTAssert(user.creds == "{\"accessToken\": \"SomeAccessTokenValue1\"}")
            XCTAssert(user.userId == 1)
            guard let credsObject = user.credsObject as? GoogleCreds else {
                XCTFail()
                return
            }
            
            XCTAssert(credsObject.accessToken == "SomeAccessTokenValue1")
            
        case .noObjectFound:
            XCTFail("No User Found")
        }
    }
}

extension SpecificDatabaseTests_UserRepository {
    static var allTests : [(String, (SpecificDatabaseTests_UserRepository) -> () throws -> Void)] {
        return [
            ("testAddOwningUser", testAddOwningUser),
            ("testAddOwningUserFailsIfYouGiveAnOwningUserId", testAddOwningUserFailsIfYouGiveAnOwningUserId),
            ("testAddOwningUserFailsIfYouGivePermissions", testAddOwningUserFailsIfYouGivePermissions),
            ("testAddSharingUser", testAddSharingUser),
            ("testUserLookup1", testUserLookup1),
            ("testUserLookup1b", testUserLookup1b),
            ("testUserLookup2", testUserLookup2)
        ]
    }
}
