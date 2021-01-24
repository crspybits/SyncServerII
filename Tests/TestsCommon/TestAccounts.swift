//
//  TestAccounts.swift
//  ServerTests
//
//  Created by Christopher G Prince on 12/17/17.
//

import Foundation
import ServerShared
@testable import Server
import LoggerAPI
import HeliumLogger
import XCTest
import ServerAccount
@testable import ServerDropboxAccount
@testable import ServerGoogleAccount
@testable import ServerMicrosoftAccount
@testable import ServerAppleSignInAccount
import ServerFacebookAccount

func ==(lhs: TestAccount, rhs:TestAccount) -> Bool {
    return lhs.tokenKey == rhs.tokenKey && lhs.idKey == rhs.idKey
}

struct TestAccount {
    let tokenKey:KeyPath<TestConfiguration, String> // key values: e.g., Google: a refresh token; Facebook:long-lived access token.
    
    // For Microsoft, their idToken
    let secondTokenKey:KeyPath<TestConfiguration, String>?
    
    let idKey:KeyPath<TestConfiguration, String>
    
    let scheme: AccountScheme
    
    // tokenKey: \.DropboxAccessTokenRevoked, idKey: \.DropboxId3, scheme: .dropbox
    init(tokenKey:KeyPath<TestConfiguration, String>, secondTokenKey:KeyPath<TestConfiguration, String>? = nil, idKey:KeyPath<TestConfiguration, String>, scheme: AccountScheme) {
        self.tokenKey = tokenKey
        self.secondTokenKey = secondTokenKey
        self.idKey = idKey
        self.scheme = scheme
    }
    
    // The main owning account on which tests are conducted.
#if PRIMARY_OWNING_GOOGLE1
    static let primaryOwningAccount:TestAccount = .google1
#elseif PRIMARY_OWNING_DROPBOX1
    static let primaryOwningAccount:TestAccount = .dropbox1
#elseif PRIMARY_OWNING_MICROSOFT1
    static let primaryOwningAccount:TestAccount = .microsoft1
#else
    static let primaryOwningAccount:TestAccount = .google1
#endif
    
    // Secondary owning account-- must be different than primary.
#if SECONDARY_OWNING_GOOGLE2
    static let secondaryOwningAccount:TestAccount = .google2
#elseif SECONDARY_OWNING_DROPBOX2
    static let secondaryOwningAccount:TestAccount = .dropbox2
#elseif SECONDARY_OWNING_MICROSOFT2
    static let secondaryOwningAccount:TestAccount = .microsoft2
#else
    static let secondaryOwningAccount:TestAccount = .google2
#endif

    // Main account, for sharing, on which tests are conducted. It should be a different specific account than primaryOwningAccount.
#if PRIMARY_SHARING_GOOGLE2
    static let primarySharingAccount:TestAccount = .google2
#elseif PRIMARY_SHARING_FACEBOOK1
    static let primarySharingAccount:TestAccount = .facebook1
#elseif PRIMARY_SHARING_DROPBOX2
    static let primarySharingAccount:TestAccount = .dropbox2
#elseif PRIMARY_SHARING_MICROSOFT2
    static let primarySharingAccount:TestAccount = .microsoft2
#else
    static let primarySharingAccount:TestAccount = .google2
#endif

    // Another sharing account -- different than the primary owning, and primary sharing accounts.
#if SECONDARY_SHARING_GOOGLE3
    static let secondarySharingAccount:TestAccount = .google3
#elseif SECONDARY_SHARING_FACEBOOK2
    static let secondarySharingAccount:TestAccount = .facebook2
#else
    static let secondarySharingAccount:TestAccount = .google3
#endif

    static let nonOwningSharingAccount:TestAccount = .facebook1
    
    static let google1 = TestAccount(tokenKey: \.GoogleRefreshToken, idKey: \.GoogleSub, scheme: AccountScheme.google)
    static let google2 = TestAccount(tokenKey: \.GoogleRefreshToken2, idKey: \.GoogleSub2, scheme: AccountScheme.google)
    static let google3 = TestAccount(tokenKey: \.GoogleRefreshToken3, idKey: \.GoogleSub3, scheme: .google)

    // https://myaccount.google.com/permissions?pli=1
    static let googleRevoked = TestAccount(tokenKey: \.GoogleRefreshTokenRevoked, idKey: \.GoogleSub4, scheme: .google)

    static func isGoogle(_ account: TestAccount) -> Bool {
        return account.scheme == AccountScheme.google
    }
    
    static func needsCloudFolder(_ account: TestAccount) -> Bool {
        return account.scheme == AccountScheme.google
    }
    
    static let facebook1 = TestAccount(tokenKey: \.FacebookLongLivedToken1, idKey: \.FacebookId1, scheme: .facebook)

    static let facebook2 = TestAccount(tokenKey: \.FacebookLongLivedToken2, idKey: \.FacebookId2, scheme: .facebook)
    
    static let dropbox1 = TestAccount(tokenKey: \.DropboxRefreshToken1, idKey: \.DropboxId1, scheme: .dropbox)
    
    static let dropbox2 = TestAccount(tokenKey: \.DropboxAccessToken2, idKey: \.DropboxId2, scheme: .dropbox)
    
    static let dropbox1Revoked = TestAccount(tokenKey: \.DropboxAccessTokenRevoked, idKey: \.DropboxId3, scheme: .dropbox)
    
    // All valid Microsoft TestAccounts are going to have secondTokens that are idTokens
    static let microsoft1 = TestAccount(tokenKey: \.microsoft1.refreshToken, secondTokenKey: \.microsoft1.idToken, idKey: \.microsoft1.id, scheme: .microsoft)
    
    static let microsoft2 = TestAccount(tokenKey: \.microsoft2.refreshToken, secondTokenKey: \.microsoft2.idToken, idKey: \.microsoft2.id, scheme: .microsoft)
    
    static let apple1 = TestAccount(tokenKey: \.apple1.idToken, secondTokenKey: \.apple1.authorizationCode, idKey: \.apple1.id, scheme: .appleSignIn)
    
    static let microsoft1ExpiredAccessToken = TestAccount(tokenKey: \.microsoft1ExpiredAccessToken.refreshToken, secondTokenKey: \.microsoft1ExpiredAccessToken.accessToken, idKey: \.microsoft1ExpiredAccessToken.id, scheme: .microsoft)
    
    static let microsoft2RevokedAccessToken = TestAccount(tokenKey: \.microsoft2RevokedAccessToken.refreshToken, secondTokenKey: \.microsoft2RevokedAccessToken.accessToken, idKey: \.microsoft2RevokedAccessToken.id, scheme: .microsoft)
    
    func token() -> String {
        return Configuration.test![keyPath: tokenKey]
    }
    
    func secondToken() -> String? {
        guard let secondTokenKey = secondTokenKey else {
            return nil
        }
        
        return Configuration.test![keyPath: secondTokenKey]
    }
    
    func id() -> String {
        return Configuration.test![keyPath: idKey]
    }
    
    static func registerHandlers() {
        // MARK: Google
        AccountScheme.google.registerHandler(type: .getCredentials) { testAccount, callback in
            CredsCache.credsFor(googleAccount: testAccount) { creds in
                callback(creds)
            }
        }
        
        // MARK: Dropbox
        AccountScheme.dropbox.registerHandler(type: .getCredentials) { testAccount, callback in
            CredsCache.credsFor(dropboxAccount: testAccount) { creds in
                callback(creds)
            }
        }
        
        // MARK: Microsoft
        AccountScheme.microsoft.registerHandler(type: .getCredentials) { testAccount, callback in
            CredsCache.credsFor(microsoftAccount: testAccount) { creds in
                callback(creds)
            }
        }
        
        // MARK: Facebook
        AccountScheme.facebook.registerHandler(type: .getCredentials) { testAccount, callback in
            guard let creds = FacebookCreds(configuration: Configuration.server, delegate: nil) else {
                XCTFail()
                return
            }
            creds.accessToken = testAccount.token()
            callback(creds)
        }

        // MARK: Apple Sign In
        AccountScheme.appleSignIn.registerHandler(type: .getCredentials) { testAccount, callback in
            guard let creds = AppleSignInCreds(configuration: Configuration.server, delegate: nil) else {
                XCTFail()
                return
            }
            creds.accessToken = testAccount.token()
            callback(creds)
        }
    }
}

typealias Handler = (TestAccount, @escaping (Account)->())->()
private var handlers = [String: Handler]()

extension AccountScheme {
    enum HandlerType: String {
        case getCredentials
    }
    
    private func key(for type: HandlerType) -> String {
        return "\(type.rawValue).\(accountName)"
    }
    
    func registerHandler(type: HandlerType, handler:@escaping Handler) {
        handlers[key(for: type)] = handler
    }
    
    func doHandler(for type: HandlerType, testAccount: TestAccount, callback: @escaping ((Account)->())) {
        let handlerKey = key(for: type)
        guard let handler = handlers[handlerKey] else {
            assert(false)
            return
        }
        
        // Log.debug("About to call handler: \(type)")
        handler(testAccount, callback)
    }
    
    // Assumes that the ServerConstants.HTTPOAuth2AccessTokenKey key has been set in the headers.
    func specificHeaderSetup(headers: inout [String: String], testUser: TestAccount) {
        switch accountName {
        case AccountScheme.dropbox.accountName:
            headers[ServerConstants.HTTPAccountIdKey] = testUser.id()
            
        case AccountScheme.microsoft.accountName:
            // Microsoft credentials are odd in that the "access token" is not a JWT Oauth2 token-- it's a specific Microsoft token.
            let msalAccessToken = headers[ServerConstants.HTTPOAuth2AccessTokenKey]
            headers[ServerConstants.HTTPMicrosoftAccessToken] = msalAccessToken

            // This is the idToken for the Microsoft account-- the real JWT Oauth2 token.
            headers[ServerConstants.HTTPOAuth2AccessTokenKey] = testUser.secondToken()
            
        default:
            break
        }
    }
    
    func deleteFile(testAccount: TestAccount, cloudFileName: String, options: CloudStorageFileNameOptions, fileNotFoundOK: Bool = false, expectation:XCTestExpectation) {

        switch testAccount.scheme.accountName {
        case AccountScheme.google.accountName:
            guard let creds = GoogleCreds(configuration: Configuration.server, delegate: nil) else {
                XCTFail()
                return
            }
            
            creds.refreshToken = testAccount.token()
            creds.refresh { error in
                guard error == nil, creds.accessToken != nil else {
                    print("Error: \(error!)")
                    XCTFail()
                    expectation.fulfill()
                    return
                }
                
                guard let cloudStorage = creds.cloudStorage(mock: MockStorage()) else {
                    XCTFail()
                    expectation.fulfill()
                    return
                }
                
                cloudStorage.deleteFile(cloudFileName:cloudFileName, options:options) { result in
                    switch result {
                    case .success:
                        break
                    case .accessTokenRevokedOrExpired:
                        XCTFail()
                    case .failure(let error):
                        Log.warning("cloudFileName: \(cloudFileName); \(error)")
                    }
                    
                    expectation.fulfill()
                }
            }
            
        case AccountScheme.dropbox.accountName:
            guard let creds = DropboxCreds(configuration: Configuration.server, delegate: nil) else {
                XCTFail()
                return
            }
            
            creds.refreshToken = testAccount.token()
            creds.accountId = testAccount.id()
            
            creds.refresh { error in
                guard error == nil, creds.accessToken != nil else {
                    Log.error("Error: \(error)")
                    XCTFail()
                    expectation.fulfill()
                    return
                }
                
                guard let cloudStorage = creds.cloudStorage(mock: MockStorage()) else {
                    XCTFail()
                    expectation.fulfill()
                    return
                }
                
                cloudStorage.deleteFile(cloudFileName:cloudFileName, options:options) { result in
                    switch result {
                    case .success:
                        break
                    case .accessTokenRevokedOrExpired:
                        XCTFail()
                    case .failure(let error):
                        if fileNotFoundOK,
                            let error = error as? DropboxCreds.DropboxError,
                            case .couldNotGetId = error {
                            expectation.fulfill()
                        }
                        else {
                            XCTFail("DropboxCreds file deletion: \(error)")
                            expectation.fulfill()
                        }
                    }

                    expectation.fulfill()
                }
            }
            
        case AccountScheme.microsoft.accountName:
            guard let creds = MicrosoftCreds(configuration: Configuration.server, delegate: nil) else {
                XCTFail()
                return
            }
            creds.refreshToken = testAccount.token()
            creds.refresh { error in
                guard error == nil, creds.accessToken != nil else {
                    print("Error: \(error!)")
                    XCTFail()
                    expectation.fulfill()
                    return
                }
                
                guard let cloudStorage = creds.cloudStorage(mock: MockStorage()) else {
                    XCTFail()
                    expectation.fulfill()
                    return
                }
                
                cloudStorage.deleteFile(cloudFileName:cloudFileName, options:options) { result in
                    switch result {
                    case .success:
                        expectation.fulfill()
                    case .accessTokenRevokedOrExpired:
                        XCTFail()
                        expectation.fulfill()
                    case .failure(let error):
                        if fileNotFoundOK,
                            let error = error as? MicrosoftCreds.OneDriveFailure,
                            case .fileNotFound = error {
                            expectation.fulfill()
                        }
                        else {
                            XCTFail("Microsoft file deletion: \(error)")
                            expectation.fulfill()
                        }
                    }
                }
            }

        default:
            assert(false)
        }
    }
}

// 12/20/17; I'm doing this because I suspect that I get test failures that occur simply because I'm asking to generate an access token from a refresh token too frequently in my tests.
class CredsCache {
    // The key is the `sub` or id for the particular account.
    static var cache = [String: Account]()
    
    static func credsFor(googleAccount:TestAccount,
                         completion: @escaping (_ creds: GoogleCreds)->()) {
        if let creds = cache[googleAccount.id()] {
            guard let creds = creds as? GoogleCreds else {
                assert(false)
                return
            }
            
            completion(creds)
        }
        else {
            Log.info("Attempting to refresh Google Creds...")
            guard let creds = GoogleCreds(configuration: Configuration.server, delegate: nil) else {
                XCTFail()
                return
            }
            cache[googleAccount.id()] = creds
            creds.refreshToken = googleAccount.token()
            creds.refresh {[unowned creds] error in
                XCTAssert(error == nil, "credsFor: Failure on refresh: \(error!)")
                completion(creds)
            }
        }
    }
    
    static func credsFor(microsoftAccount:TestAccount,
                         completion: @escaping (_ creds: MicrosoftCreds)->()) {
        if let creds = cache[microsoftAccount.id()] {
            guard let creds = creds as? MicrosoftCreds else {
                assert(false)
                return
            }
            completion(creds)
        }
        else {
            Log.info("Attempting to refresh Microsoft Creds...")
            guard let creds = MicrosoftCreds(configuration: Configuration.server, delegate: nil) else {
                XCTFail()
                return
            }
            cache[microsoftAccount.id()] = creds
            creds.refreshToken = microsoftAccount.token()
            creds.refresh {[unowned creds] error in
                XCTAssert(error == nil, "credsFor: Failure on refresh: \(error!)")
                completion(creds)
            }
        }
    }
    
    static func credsFor(dropboxAccount:TestAccount,
                         completion: @escaping (_ creds: DropboxCreds)->()) {
        if let creds = cache[dropboxAccount.id()] {
            guard let creds = creds as? DropboxCreds else {
                assert(false)
                return
            }
            
            completion(creds)
        }
        else {
            Log.info("Attempting to refresh Dropbox Creds...")
            guard let creds = DropboxCreds(configuration: Configuration.server, delegate: nil) else {
                XCTFail()
                return
            }
            cache[dropboxAccount.id()] = creds
            creds.refreshToken = dropboxAccount.token()
            creds.refresh {[unowned creds] error in
                XCTAssert(error == nil, "credsFor: Failure on refresh: \(error!)")
                completion(creds)
            }
        }
    }
}

extension XCTestCase {
    @discardableResult
    func lookupFile(forOwningTestAccount testAccount: TestAccount, cloudFileName: String, options: CloudStorageFileNameOptions) -> Bool? {
    
        var lookupResult: Bool?
        
        let expectation = self.expectation(description: "expectation")
    
        switch testAccount.scheme.accountName {
        case AccountScheme.google.accountName:
            guard let creds = GoogleCreds(configuration: Configuration.server, delegate: nil) else {
                XCTFail()
                return nil
            }
            creds.refreshToken = testAccount.token()
            creds.refresh { error in
                guard error == nil, creds.accessToken != nil else {
                    XCTFail()
                    expectation.fulfill()
                    return
                }
            
                creds.lookupFile(cloudFileName:cloudFileName, options:options) { result in
                    switch result {
                    case .success (let found):
                        lookupResult = found
                    case .failure, .accessTokenRevokedOrExpired:
                        XCTFail()
                    }
                    
                    expectation.fulfill()
                }
            }
            
        case AccountScheme.dropbox.accountName:
            guard let creds = DropboxCreds(configuration: Configuration.server, delegate: nil) else {
                XCTFail()
                return nil
            }
            creds.accessToken = testAccount.token()
            creds.accountId = testAccount.id()
            
            creds.lookupFile(cloudFileName:cloudFileName, options:options) { result in
                switch result {
                case .success (let found):
                    lookupResult = found
                case .failure, .accessTokenRevokedOrExpired:
                    XCTFail()
                }
                
                expectation.fulfill()
            }
            
        case AccountScheme.microsoft.accountName:
            guard let creds = MicrosoftCreds(configuration: Configuration.server, delegate: nil) else {
                XCTFail()
                return nil
            }
            creds.refreshToken = testAccount.token()
            creds.refresh { error in
                guard error == nil, creds.accessToken != nil else {
                    XCTFail()
                    expectation.fulfill()
                    return
                }
            
                creds.lookupFile(cloudFileName:cloudFileName, options:options) { result in
                    switch result {
                    case .success (let found):
                        lookupResult = found
                    case .failure, .accessTokenRevokedOrExpired:
                        XCTFail()
                    }
                    
                    expectation.fulfill()
                }
            }
            
        default:
            assert(false)
        }
        
        waitForExpectations(timeout: 10.0, handler: nil)
        
        return lookupResult
    }
}
