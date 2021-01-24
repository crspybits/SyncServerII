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
import Foundation

class SpecificDatabaseTests_UserRepository: ServerTestCase, LinuxTestable {

    override func setUp() {
        super.setUp()
        AccountManager.session.reset()
    }
    
    func addOwningUsers() {
        let user1 = User()
        user1.username = "Chris"
        user1.accountType = .Google
        user1.creds = "{\"accessToken\": \"SomeAccessTokenValue1\"}"
        user1.credsId = "100"
        user1.cloudFolderName = "folder1"
        
        let result1 = UserRepository(db).add(user: user1, validateJSON: false)
        XCTAssert(result1 == 1, "Bad credentialsId!")

        let user2 = User()
        user2.username = "Natasha"
        user2.accountType = .Google
        user2.creds = "{\"accessToken\": \"SomeAccessTokenValue2\"}"
        user2.credsId = "200"
        user2.cloudFolderName = "folder2"
        
        let result2 = UserRepository(db).add(user: user2, validateJSON: false)
        XCTAssert(result2 == 2, "Bad credentialsId!")
    }
    
    func testAddOwningUser() {
        addOwningUsers()
    }
    
    func testAddOwningUserWorksIfYouGivePermissions() {
        let user1 = User()
        user1.username = "Chris"
        user1.accountType = .Google
        user1.creds = "{\"accessToken\": \"SomeAccessTokenValue1\"}"
        user1.credsId = "100"
        
        guard let _ = UserRepository(db).add(user: user1, validateJSON: false) else {
            XCTFail()
            return
        }
    }
    
    func addUser(accountType:AccountType = .Google, sharing: Bool = true) {
        let user1 = User()
        user1.username = "Chris"
        user1.accountType = accountType
        
        switch (accountType) {
        case .Google:
            user1.creds = "{\"accessToken\": \"SomeAccessTokenValue1\"}"
        case .Facebook:
            user1.creds = "{}"
        case .Dropbox:
            user1.creds = "{\"accessToken\": \"SomeAccessTokenValue1\"}"
        }
        
        user1.credsId = "100"
        

        guard let _ = UserRepository(db).add(user: user1, validateJSON: false) else {
            XCTFail()
            return
        }
    }
    
    func testAddGoogleUser() {
        addUser(sharing: false)
    }
    
    func testAddSharingFacebookUser() {
        addUser(accountType: .Facebook)
    }
    
    func testAddDropboxUser() {
        addUser(accountType: .Dropbox, sharing: false)
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
            XCTAssert(user.cloudFolderName == "folder1")
            
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
            XCTAssert(user.cloudFolderName == "folder1")
            
        case .noObjectFound:
            XCTFail("No User Found")
        }
    }
    
    func testUserLookup2() {
        // Faking this so we don't have to startup server.
        AccountManager.session.addAccountType(GoogleCreds.self)
        
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
            XCTAssert(user.cloudFolderName == "folder1")

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
            ("testAddOwningUserWorksIfYouGivePermissions", testAddOwningUserWorksIfYouGivePermissions),
            
            ("testAddGoogleUser", testAddGoogleUser),
            ("testAddSharingFacebookUser", testAddSharingFacebookUser),
            ("testAddDropboxUser", testAddDropboxUser),
            
            ("testUserLookup1", testUserLookup1),
            ("testUserLookup1b", testUserLookup1b),
            ("testUserLookup2", testUserLookup2)
        ]
    }
    
    func testLinuxTestSuiteIncludesAllTests() {
        linuxTestSuiteIncludesAllTests(testType: SpecificDatabaseTests_UserRepository.self)
    }
}
