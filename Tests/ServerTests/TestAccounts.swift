//
//  TestAccounts.swift
//  ServerTests
//
//  Created by Christopher G Prince on 12/17/17.
//

import Foundation
import SyncServerShared
import SMServerLib
@testable import Server
import LoggerAPI
import HeliumLogger
import XCTest

func ==(lhs: TestAccount, rhs:TestAccount) -> Bool {
    return lhs.tokenKey == rhs.tokenKey && lhs.idKey == rhs.idKey
}

struct TestAccount {
    // These String's are keys into a .json file.
    
    let tokenKey:KeyPath<TestConfiguration, String> // key values: e.g., Google: a refresh token; Facebook:long-lived access token.
    let idKey:KeyPath<TestConfiguration, String>
    
    let scheme: AccountScheme
    
    // The main owning account on which tests are conducted.
#if PRIMARY_OWNING_GOOGLE1
    static let primaryOwningAccount:TestAccount = .google1
#elseif PRIMARY_OWNING_DROPBOX1
    static let primaryOwningAccount:TestAccount = .dropbox1
#else
    static let primaryOwningAccount:TestAccount = .google1
#endif
    
    // Secondary owning account-- must be different than primary.
#if SECONDARY_OWNING_GOOGLE2
    static let secondaryOwningAccount:TestAccount = .google2
#elseif SECONDARY_OWNING_DROPBOX2
    static let secondaryOwningAccount:TestAccount = .dropbox2
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
    
    static let dropbox1 = TestAccount(tokenKey: \.DropboxAccessToken1, idKey: \.DropboxId1, scheme: .dropbox)
    
    static let dropbox2 = TestAccount(tokenKey: \.DropboxAccessToken2, idKey: \.DropboxId2, scheme: .dropbox)
    
    static let dropbox1Revoked = TestAccount(tokenKey: \.DropboxAccessTokenRevoked, idKey: \.DropboxId3, scheme: .dropbox)
    
    static let microsoft1 = TestAccount(tokenKey: \.microsoft1.refreshToken, idKey: \.microsoft1.id, scheme: .microsoft)
    
    // I've put this method here (instead of in Constants) because it is just a part of testing, not part of the full-blown server.
    private func configValue(key:String) -> String {
#if os(macOS)
        let config = try! ConfigLoader(usingPath: "/tmp", andFileName: "ServerTests.json", forConfigType: .jsonDictionary)
#else // Linux
        let config = try! ConfigLoader(usingPath: "./", andFileName: "ServerTests.json", forConfigType: .jsonDictionary)
#endif
        let token = try! config.getString(varName: key)
        return token
    }
    
    func token() -> String {
        return Configuration.test![keyPath: tokenKey]
    }
    
    func id() -> String {
        return Configuration.test![keyPath: idKey]
    }
    
    func registerHandlers() {
        // MARK: Google
        AccountScheme.google.registerHandler(type: .getCredentials) { testAccount, callback in
            GoogleCredsCache.credsFor(googleAccount: testAccount) { creds in
                callback(creds)
            }
        }
        
        // MARK: Dropbox
        AccountScheme.dropbox.registerHandler(type: .getCredentials) { testAccount, callback in
            let creds = DropboxCreds()
            creds.accessToken = testAccount.token()
            creds.accountId = testAccount.id()
            callback(creds)
        }
        
        // MARK: Facebook
        AccountScheme.facebook.registerHandler(type: .getCredentials) { testAccount, callback in
            let creds = FacebookCreds()
            creds.accessToken = testAccount.token()
            callback(creds)
        }
        
        // MARK: Microsoft
        AccountScheme.microsoft.registerHandler(type: .getCredentials) { testAccount, callback in
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
        guard let handler = handlers[key(for: type)] else {
            assert(false)
            return
        }
        
        handler(testAccount, callback)
    }
}

// 12/20/17; I'm doing this because I suspect that I get test failures that occur simply because I'm asking to generate an access token from a refresh token too frequently in my tests.
class GoogleCredsCache {
    // The key is the `sub` or id for the particular account.
    static var cache = [String: GoogleCreds]()
    
    static func credsFor(googleAccount:TestAccount,
                         completion: @escaping (_ creds: GoogleCreds)->()) {
        
        if let creds = cache[googleAccount.id()] {
            completion(creds)
        }
        else {
            Log.info("Attempting to refresh Google Creds...")
            let creds = GoogleCreds()
            cache[googleAccount.id()] = creds
            creds.refreshToken = googleAccount.token()
            creds.refresh {[unowned creds] error in
                XCTAssert(error == nil, "credsFor: Failure on refresh: \(error!)")
                completion(creds)
            }
        }
    }
}
