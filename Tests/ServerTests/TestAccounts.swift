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

func ==(lhs: TestAccount, rhs:TestAccount) -> Bool {
    return lhs.tokenKey == rhs.tokenKey && lhs.idKey == rhs.idKey
}

struct TestAccount {
    // These String's are keys into a .json file.
    let tokenKey:String // key values: e.g., Google: a refresh token; Facebook:long-lived access token.
    let idKey:String
    
    let type:AccountType
    let tokenType:ServerConstants.AuthTokenType
    
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

    // Main account, for sharing, on which tests are conducted. This account must allow sharing (e.g., not for Dropbox). It should be a different specific account than primaryOwningAccount.
#if PRIMARY_SHARING_GOOGLE2
    static let primarySharingAccount:TestAccount = .google2
#elseif PRIMARY_SHARING_FACEBOOK1
    static let primarySharingAccount:TestAccount = .facebook1
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

    static let google1 = TestAccount(tokenKey: "GoogleRefreshToken", idKey: "GoogleSub", type: .Google, tokenType: .GoogleToken)
    static let google2 = TestAccount(tokenKey: "GoogleRefreshToken2", idKey: "GoogleSub2", type: .Google, tokenType: .GoogleToken)
    static let google3 = TestAccount(tokenKey: "GoogleRefreshToken3", idKey: "GoogleSub3", type: .Google, tokenType: .GoogleToken)
    
    static func isGoogle(_ account: TestAccount) -> Bool {
        return account.type == .Google
    }
    
    static func needsCloudFolder(_ account: TestAccount) -> Bool {
        return account.type == .Google
    }
    
    static let facebook1 = TestAccount(tokenKey: "FacebookLongLivedToken1", idKey: "FacebookId1", type: .Facebook, tokenType: .FacebookToken)

    static let facebook2 = TestAccount(tokenKey: "FacebookLongLivedToken2", idKey: "FacebookId2", type: .Facebook, tokenType: .FacebookToken)
    
    static let dropbox1 = TestAccount(tokenKey: "DropboxAccessToken1", idKey: "DropboxId1", type: .Dropbox, tokenType: .DropboxToken)
    
    static let dropbox2 = TestAccount(tokenKey: "DropboxAccessToken2", idKey: "DropboxId2", type: .Dropbox, tokenType: .DropboxToken)
    
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
        return configValue(key: tokenKey)
    }
    
    func id() -> String {
        return configValue(key: idKey)
    }
}
