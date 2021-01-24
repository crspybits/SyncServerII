//
//  IntegrationDatabaseTests.swift
//  DatabaseTests
//
//  Created by Christopher G Prince on 8/25/20.
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
import ServerAccount

class IntegrationDatabaseTests: ServerTestCase {
    var accountManager: AccountManager!
    var userRepo: UserRepository!
    
    override func setUp() {
        super.setUp()
        userRepo = UserRepository(db)
        accountManager = AccountManager()
    }

    // For https://github.com/SyncServerII/ServerMain/issues/4
    func testFakeAddUser() {        
        // Faking this so we don't have to startup server.
        accountManager.addAccountType(GoogleCreds.self)
        
        let credsId = "100"
        
        guard db.startTransaction() else {
            XCTFail()
            return
        }
        
        let key = UserRepository.LookupKey.accountTypeInfo(accountType: AccountScheme.google.accountName, credsId: credsId)
        let userLookupResult = UserRepository(db).lookup(key: key, modelInit: User.init)
        switch userLookupResult {
        case .noObjectFound:
            break
        default:
            XCTFail()
            return
        }
        
        let user1 = User()
        user1.username = "Chris"
        user1.accountType = AccountScheme.google.accountName
        user1.creds = "{\"accessToken\": \"SomeAccessTokenValue1\"}"
        user1.credsId = credsId
        user1.cloudFolderName = "folder1"
        
        let accountDelegate = UserRepository.AccountDelegateHandler(userRepository: userRepo, accountManager: accountManager)
        guard let userId = userRepo.add(user: user1, accountManager: accountManager, accountDelegate: accountDelegate, validateJSON: false) else {
            XCTFail()
            return
        }
        
        user1.userId = userId
        
        let sharingGroupUUID = UUID().uuidString
        let addSharingGroupResult = SharingGroupRepository(db).add(sharingGroupUUID: sharingGroupUUID)
        switch addSharingGroupResult {
        case .error:
            XCTFail()
            return
        case .success:
            break
        }
        
        let permission: Permission = .read
        
        let addSharingGroupUserResult = SharingGroupUserRepository(db).add(sharingGroupUUID: sharingGroupUUID, userId: userId, permission: permission, owningUserId: nil)
        switch addSharingGroupUserResult {
        case .error:
            XCTFail()
            return
        case .success:
            break
        }
        
        guard let credsJSON = user1.creds, let creds = try? accountManager.accountFromJSON(credsJSON, accountName: user1.accountType, user: .user(user1), accountDelegate: accountDelegate) else {
            XCTFail()
            return
        }
        
        let accountCreationUser = AccountCreationUser.user(user1)
        guard userRepo.updateCreds(creds: creds, forUser: accountCreationUser, accountManager: accountManager) else {
            XCTFail()
            return
        }
        
        guard db.commit() else {
            XCTFail()
            return
        }
    }
}
