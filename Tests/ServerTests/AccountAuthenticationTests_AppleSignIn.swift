//
//  AccountAuthenticationTests_AppleSignIn.swift
//  ServerTests
//
//  Created by Christopher G Prince on 10/5/19.
//

import XCTest
@testable import Server
import LoggerAPI
import HeliumLogger

class AccountAuthenticationTests_AppleSignIn: ServerTestCase, LinuxTestable {
    func testClientSecretGenerationWorks() {
        guard let appleSignInCreds = AppleSignInCreds() else {
            XCTFail()
            return
        }
        
        let secret = appleSignInCreds.createClientSecret()
        XCTAssert(secret != nil)
    }
    
    // This has to be tested by hand-- since the authorization codes expire in 5 minutes and can only be used once. Before running this test, populate a auth code into the apple1 account first-- this can be generated from the iOS app.
#if false
    func testGenerateRefreshToken() {
        guard let appleSignInCreds = AppleSignInCreds() else {
            XCTFail()
            return
        }
        
        let testAccount: TestAccount = .apple1
        
        guard let authorizationCode = testAccount.secondToken() else {
            XCTFail()
            return
        }
        
        let exp = expectation(description: "generate")
        appleSignInCreds.generateRefreshToken(serverAuthCode: authorizationCode) { error in
            XCTAssert(error == nil, "\(String(describing: error))")
            
            XCTAssert(appleSignInCreds.accessToken != nil)
            XCTAssert(appleSignInCreds.refreshToken != nil)
            XCTAssert(appleSignInCreds.lastRefreshTokenUsage != nil)

            exp.fulfill()
        }
        waitForExpectations(timeout: 10, handler: nil)
    }
#endif

    // This also has to be tested by hand-- since a refresh token can only be used at most every 24 hours
    func testValidateRefreshToken() {
        guard let appleSignInCreds = AppleSignInCreds() else {
            XCTFail()
            return
        }
        
        let testAccount: TestAccount = .apple1
        let refreshToken = testAccount.token()
        appleSignInCreds.refreshToken = refreshToken
        
        let exp = expectation(description: "refresh")
        
        appleSignInCreds.validateRefreshToken() { error in
            XCTAssert(error == nil, "\(String(describing: error))")

            XCTAssert(appleSignInCreds.lastRefreshTokenValidation != nil)
            
            exp.fulfill()
        }

        waitForExpectations(timeout: 10, handler: nil)
    }
}

extension AccountAuthenticationTests_AppleSignIn {
    static var allTests : [(String, (AccountAuthenticationTests_AppleSignIn) -> () throws -> Void)] {
        let result:[(String, (AccountAuthenticationTests_AppleSignIn) -> () throws -> Void)] = [
            ("testClientSecretGenerationWorks", testClientSecretGenerationWorks),
            ]
        
        return result
    }
    
    func testLinuxTestSuiteIncludesAllTests() {
        linuxTestSuiteIncludesAllTests(testType:AccountAuthenticationTests_AppleSignIn.self)
    }
}
