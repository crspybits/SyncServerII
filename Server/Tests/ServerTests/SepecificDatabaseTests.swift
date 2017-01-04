//
//  SepecificDatabaseTests.swift
//  Server
//
//  Created by Christopher Prince on 12/18/16.
//
//

import XCTest
@testable import Server
import LoggerAPI
import HeliumLogger
import Credentials
import CredentialsGoogle

class SepecificDatabaseTests: XCTestCase {

    override func setUp() {
        super.setUp()
        _ = UserRepository.remove()
        _ = UserRepository.create()
    }
    
    override func tearDown() {
        super.tearDown()
    }
    
    func testAddUser() {
        let user1 = User()
        user1.username = "Chris"
        user1.accountType = .Google
        user1.creds = "{\"accessToken\": \"SomeAccessTokenValue1\"}"
        user1.credsId = "100"
        
        let result1 = UserRepository.add(user: user1)
        XCTAssert(result1 == 1, "Bad credentialsId!")

        let user2 = User()
        user2.username = "Natasha"
        user2.accountType = .Google
        user2.creds = "{\"accessToken\": \"SomeAccessTokenValue2\"}"
        user2.credsId = "200"
        
        let result2 = UserRepository.add(user: user2)
        XCTAssert(result2 == 2, "Bad credentialsId!")
    }
    
    func testLookup1() {
        testAddUser()
        
        let result = UserRepository.lookup(key: .userId(1))
        switch result {
        case .error(let error):
            XCTFail("\(error)")
            
        case .found(let user):
            XCTAssert(user.accountType == .Google)
            XCTAssert(user.username == "Chris")
            XCTAssert(user.creds == "{\"accessToken\": \"SomeAccessTokenValue1\"}")
            XCTAssert(user.userId == 1)
            
        case .noUserFound:
            XCTFail("No User Found")
        }
    }
    
    func testLookup2() {
        testAddUser()
        
        let result = UserRepository.lookup(key: .accountTypeInfo(accountType:.Google, credsId:"100"))
        switch result {
        case .error(let error):
            XCTFail("\(error)")
            
        case .found(let user):
            XCTAssert(user.accountType == .Google)
            XCTAssert(user.username == "Chris")
            XCTAssert(user.creds == "{\"accessToken\": \"SomeAccessTokenValue1\"}")
            XCTAssert(user.userId == 1)
            guard let credsObject = user.credsObject as? GoogleCreds else {
                XCTFail()
                return
            }
            
            XCTAssert(credsObject.accessToken == "SomeAccessTokenValue1")
            
        case .noUserFound:
            XCTFail("No User Found")
        }
    }
}
