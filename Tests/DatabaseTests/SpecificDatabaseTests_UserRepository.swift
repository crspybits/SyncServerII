//
//  SpecificDatabaseTests_UserRepository.swift
//  Server
//
//  Created by Christopher Prince on 4/11/17.
//
//

import XCTest
@testable import Server
@testable import TestsCommon
import LoggerAPI
import HeliumLogger
import Credentials
import CredentialsGoogle
import Foundation
import ServerShared
import ServerGoogleAccount

class SpecificDatabaseTests_UserRepository: ServerTestCase {
    var accountManager: AccountManager!
    var userRepo: UserRepository!
    
    override func setUp() {
        super.setUp()
        userRepo = UserRepository(db)
        accountManager = AccountManager(userRepository: userRepo)
    }
    
    func addOwningUsers() {
        let user1 = User()
        user1.username = "Chris"
        user1.accountType = AccountScheme.google.accountName
        user1.creds = "{\"accessToken\": \"SomeAccessTokenValue1\"}"
        user1.credsId = "100"
        user1.cloudFolderName = "folder1"
        
        let result1 = userRepo.add(user: user1, accountManager: accountManager, validateJSON: false)
        XCTAssert(result1 == 1, "Bad credentialsId!")

        let user2 = User()
        user2.username = "Natasha"
        user2.accountType = AccountScheme.google.accountName
        user2.creds = "{\"accessToken\": \"SomeAccessTokenValue2\"}"
        user2.credsId = "200"
        user2.cloudFolderName = "folder2"
        
        let result2 = userRepo.add(user: user2, accountManager: accountManager, validateJSON: false)
        XCTAssert(result2 == 2, "Bad credentialsId!")
    }
    
    func testAddOwningUser() {
        addOwningUsers()
    }
    
    func testAddOwningUserWorksIfYouGivePermissions() {
        let user1 = User()
        user1.username = "Chris"
        user1.accountType = AccountScheme.google.accountName
        user1.creds = "{\"accessToken\": \"SomeAccessTokenValue1\"}"
        user1.credsId = "100"
        
        guard let _ = userRepo.add(user: user1, accountManager: accountManager, validateJSON: false) else {
            XCTFail()
            return
        }
    }
    
    func addUser(accountType:AccountScheme.AccountName = AccountScheme.google.accountName, sharing: Bool = true) {
        let user1 = User()
        user1.username = "Chris"
        user1.accountType = accountType
        
        switch (accountType) {
        case AccountScheme.google.accountName:
            user1.creds = "{\"accessToken\": \"SomeAccessTokenValue1\"}"
        case AccountScheme.facebook.accountName:
            user1.creds = "{}"
        case AccountScheme.dropbox.accountName:
            user1.creds = "{\"accessToken\": \"SomeAccessTokenValue1\"}"
        default:
            XCTFail()
        }
        
        user1.credsId = "100"
        

        guard let _ = userRepo.add(user: user1, accountManager: accountManager, validateJSON: false) else {
            XCTFail()
            return
        }
    }
    
    func testAddGoogleUser() {
        addUser(sharing: false)
    }
    
    func testAddSharingFacebookUser() {
        addUser(accountType: AccountScheme.facebook.accountName)
    }
    
    func testAddDropboxUser() {
        addUser(accountType: AccountScheme.dropbox.accountName, sharing: false)
    }
    
    func testUserLookup1() {
        addOwningUsers()
        
        let result = UserRepository(db).lookup(key: .userId(1), modelInit:User.init)
        switch result {
        case .error(let error):
            XCTFail("\(error)")
            
        case .found(let object):
            let user = object as! User
            XCTAssert(user.accountType == AccountScheme.google.accountName)
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
            XCTAssert(user.accountType == AccountScheme.google.accountName)
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
        accountManager.addAccountType(GoogleCreds.self)
        
        addOwningUsers()

        let result = userRepo.lookup(key: .accountTypeInfo(accountType:AccountScheme.google.accountName, credsId:"100"), modelInit:User.init)
        switch result {
        case .error(let error):
            XCTFail("\(error)")
            
        case .found(let object):
            let user = object as! User
            XCTAssert(user.accountType == AccountScheme.google.accountName)
            XCTAssert(user.username == "Chris")
            XCTAssert(user.creds == "{\"accessToken\": \"SomeAccessTokenValue1\"}")
            XCTAssert(user.userId == 1)
            XCTAssert(user.cloudFolderName == "folder1")

            guard let credsObject = try? accountManager.accountFromJSON(user.creds, accountName: user.accountType, user: .user(user)) else {
                XCTFail()
                return
            }
            
            XCTAssert(credsObject.accessToken == "SomeAccessTokenValue1")
            
        case .noObjectFound:
            XCTFail("No User Found")
        }
    }
}
