//
//  AccountAuthenticationTests_AppleSignIn.swift
//  ServerTests
//
//  Created by Christopher G Prince on 10/5/19.
//

import XCTest
@testable import Server
@testable import TestsCommon
import LoggerAPI
import HeliumLogger

class AccountAuthenticationTests_AppleSignIn: ServerTestCase, LinuxTestable {

// Until I get dev & testing done, don't worry about AppleSignIn
#if false
    func testClientSecretGenerationWorks() {
        guard let appleSignInCreds = AppleSignInCreds() else {
            XCTFail()
            return
        }
        
        let secret = appleSignInCreds.createClientSecret()
        XCTAssert(secret != nil)
    }
#endif

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

    // This also has to be tested by hand-- since a refresh token can only be used at most every 24 hours
    func testValidateRefreshToken() {
        guard let appleSignInCreds = AppleSignInCreds() else {
            XCTFail()
            return
        }
        
        let testAccount: TestAccount = .apple1
        let refreshToken = testAccount.token()
        
        let exp = expectation(description: "refresh")
        
        appleSignInCreds.validateRefreshToken(refreshToken: refreshToken) { error in
            XCTAssert(error == nil, "\(String(describing: error))")

            XCTAssert(appleSignInCreds.lastRefreshTokenValidation != nil)
            
            exp.fulfill()
        }

        waitForExpectations(timeout: 10, handler: nil)
    }
#endif

// Until I get dev & testing done, don't worry about AppleSignIn
#if false
    class CredsDelegate: AccountDelegate {
        func saveToDatabase(account: Account) -> Bool {
            return false
        }
    }
    
    // No dbCreds, serverAuthCode, lastRefreshTokenValidation, refreshToken
    func testNeedToGenerateTokensNoGeneration() {
        guard let appleSignInCreds = AppleSignInCreds() else {
            XCTFail()
            return
        }
        
        let delegate = CredsDelegate()
        appleSignInCreds.delegate = delegate
                        
        let result = appleSignInCreds.needToGenerateTokens(dbCreds: nil)
        XCTAssert(!result)
        
        switch appleSignInCreds.generateTokens {
        case .some(.noGeneration):
            break
        default:
            XCTFail()
        }
    }
#endif
}

extension AccountAuthenticationTests_AppleSignIn {
    static var allTests : [(String, (AccountAuthenticationTests_AppleSignIn) -> () throws -> Void)] {
        let result:[(String, (AccountAuthenticationTests_AppleSignIn) -> () throws -> Void)] = [
                /*
                ("testClientSecretGenerationWorks", testClientSecretGenerationWorks),
                ("testNeedToGenerateTokensNoGeneration", testNeedToGenerateTokensNoGeneration)
                */
            ]
        
        return result
    }
    
    func testLinuxTestSuiteIncludesAllTests() {
        linuxTestSuiteIncludesAllTests(testType:AccountAuthenticationTests_AppleSignIn.self)
    }
}
