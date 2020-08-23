//
//  SharingAccountsController_RedeemSharingInvitation.swift
//  Server
//
//  Created by Christopher Prince on 4/12/17.
//
//

import XCTest
@testable import Server
@testable import TestsCommon
import LoggerAPI
import Foundation
import ServerShared

class SharingAccountsController_RedeemSharingInvitation: ServerTestCase {

    override func setUp() {
        super.setUp()
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }
    
    override func tearDown() {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
        super.tearDown()
    }
    
    func testThatRedeemingWithASharingAccountWorks() {
        let sharingUser:TestAccount = .primarySharingAccount
        let owningUser:TestAccount = .primaryOwningAccount

        var sharingGroupUUID: String!
        var newSharingUserId: UserId!
        
        createSharingUser(sharingUser: sharingUser, owningUserWhenCreating: owningUser) { userId, sid, _ in
            sharingGroupUUID = sid
            newSharingUserId = userId
        }
        
        guard sharingGroupUUID != nil else {
            XCTFail()
            return
        }

        checkOwingUserForSharingGroupUser(sharingGroupUUID: sharingGroupUUID, sharingUserId: newSharingUserId, sharingUser: sharingUser, owningUser: owningUser)
    }
    
    // Requires that Facebook creds be up to date.
    func testThatRedeemingWithANonOwningSharingAccountWorks() {
        let sharingUser:TestAccount = .nonOwningSharingAccount
        let owningUser:TestAccount = .primaryOwningAccount

        var sharingGroupUUID: String!
        var newSharingUserId: UserId!
        
        createSharingUser(sharingUser: sharingUser, owningUserWhenCreating: owningUser) { userId, sid, _ in
            sharingGroupUUID = sid
            newSharingUserId = userId
        }
        
        guard sharingGroupUUID != nil else {
            XCTFail()
            return
        }

        guard checkOwingUserForSharingGroupUser(sharingGroupUUID: sharingGroupUUID, sharingUserId: newSharingUserId, sharingUser: sharingUser, owningUser: owningUser) else {
            XCTFail()
            return
        }

        guard let (_, sharingGroups) = getIndex(testAccount: sharingUser), sharingGroups.count > 0 else {
            XCTFail()
            return
        }
        
        var found = false
        
        for sharingGroup in sharingGroups {
            if sharingGroup.sharingGroupUUID == sharingGroupUUID {
                guard let cloudStorageType = sharingGroup.cloudStorageType else {
                    XCTFail()
                    return
                }
         
                XCTAssert(owningUser.scheme.cloudStorageType == cloudStorageType)
                found = true
            }
        }
        
        XCTAssert(found)
    }
    
    func testThatRedeemingUsingGoogleAccountWithoutCloudFolderNameFails() {
        let permission:Permission = .write
        let sharingUser:TestAccount = .google2

        let deviceUUID = Foundation.UUID().uuidString
        let sharingGroupUUID = Foundation.UUID().uuidString

        guard let _ = self.addNewUser(sharingGroupUUID: sharingGroupUUID, deviceUUID:deviceUUID) else {
            XCTFail()
            return
        }

        let sharingInvitationUUID:String! = createSharingInvitation(permission: permission, sharingGroupUUID:sharingGroupUUID)
        guard sharingInvitationUUID != nil else {
            XCTFail()
            return
        }
        
        let result = redeemSharingInvitation(sharingUser:sharingUser, canGiveCloudFolderName: false, sharingInvitationUUID: sharingInvitationUUID, errorExpected: true)
        XCTAssert(result == nil)
    }
        
    func redeemingASharingInvitationWithoutGivingTheInvitationUUIDFails(sharingUser: TestAccount) {
        let deviceUUID = Foundation.UUID().uuidString
        let sharingGroupUUID = Foundation.UUID().uuidString

        guard let _ = self.addNewUser(sharingGroupUUID: sharingGroupUUID, deviceUUID:deviceUUID) else {
            XCTFail()
            return
        }

        let result = redeemSharingInvitation(sharingUser: sharingUser, errorExpected:true)
        XCTAssert(result == nil)
    }
    
    func testThatRedeemingASharingInvitationByAUserWithoutGivingTheInvitationUUIDFails() {
        redeemingASharingInvitationWithoutGivingTheInvitationUUIDFails(sharingUser:
            .primarySharingAccount)
    }

    func testThatRedeemingWithTheSameAccountAsTheOwningAccountFails() {
        let deviceUUID = Foundation.UUID().uuidString
        let sharingGroupUUID = Foundation.UUID().uuidString
        guard let _ = self.addNewUser(sharingGroupUUID: sharingGroupUUID, deviceUUID:deviceUUID) else {
            XCTFail()
            return
        }
        
        let sharingInvitationUUID:String! = createSharingInvitation(permission: .read, sharingGroupUUID: sharingGroupUUID)
        guard sharingInvitationUUID != nil else {
            XCTFail()
            return
        }
        
        let result = redeemSharingInvitation(sharingUser: .primaryOwningAccount, sharingInvitationUUID: sharingInvitationUUID, errorExpected:true)
        XCTAssert(result == nil)
    }
    
    // 8/12/18; This now works-- i.e., you can redeem with other owning accounts-- because each user can now be in multiple sharing groups. (Prior to this, it was a failure test!).
    func testThatRedeemingWithAnExistingOtherOwningAccountWorks() {
        let deviceUUID = Foundation.UUID().uuidString
        let sharingGroupUUID1 = Foundation.UUID().uuidString
        let owningAccount:TestAccount = .primaryOwningAccount

        guard let _ = self.addNewUser(testAccount: owningAccount, sharingGroupUUID: sharingGroupUUID1, deviceUUID:deviceUUID) else {
            XCTFail()
            return
        }

        let sharingInvitationUUID:String! = createSharingInvitation(testAccount: owningAccount, permission: .read, sharingGroupUUID:sharingGroupUUID1)
        guard sharingInvitationUUID != nil else {
            XCTFail()
            return
        }
        
        let secondOwningAccount:TestAccount = .secondaryOwningAccount
        let deviceUUID2 = Foundation.UUID().uuidString
        let sharingGroupUUID2 = Foundation.UUID().uuidString
        addNewUser(testAccount: secondOwningAccount, sharingGroupUUID: sharingGroupUUID2, deviceUUID:deviceUUID2)
        
        let result: RedeemSharingInvitationResponse! = redeemSharingInvitation(sharingUser: secondOwningAccount, sharingInvitationUUID: sharingInvitationUUID)
        guard result != nil else {
            XCTFail()
            return
        }
        
        checkOwingUserForSharingGroupUser(sharingGroupUUID: sharingGroupUUID2, sharingUserId: result.userId, sharingUser: secondOwningAccount, owningUser: owningAccount)
    }
    
    // Redeem sharing invitation for existing user: Works if user isn't already in sharing group
    func testThatRedeemingWithAnExistingOtherSharingAccountWorks() {
        redeemWithAnExistingOtherSharingAccount()
    }
    
    func redeemingForSameSharingGroupFails(sharingUser: TestAccount) {
        let deviceUUID = Foundation.UUID().uuidString
        let sharingGroupUUID = Foundation.UUID().uuidString

        guard let _ = self.addNewUser(sharingGroupUUID: sharingGroupUUID, deviceUUID:deviceUUID) else {
            XCTFail()
            return
        }
            
        var sharingInvitationUUID:String! = createSharingInvitation(permission: .read, sharingGroupUUID: sharingGroupUUID)
        guard sharingInvitationUUID != nil else {
            XCTFail()
            return
        }

        guard let _ = redeemSharingInvitation(sharingUser: sharingUser, sharingInvitationUUID: sharingInvitationUUID) else {
            XCTFail()
            return
        }
            
        // Check to make sure we have a new user:
        let userKey = UserRepository.LookupKey.accountTypeInfo(accountType: sharingUser.scheme.accountName, credsId: sharingUser.id())
        let userResults = UserRepository(self.db).lookup(key: userKey, modelInit: User.init)
        guard case .found(_) = userResults else {
            XCTFail()
            return
        }
            
        let key = SharingInvitationRepository.LookupKey.sharingInvitationUUID(uuid: sharingInvitationUUID)
        let results = SharingInvitationRepository(self.db).lookup(key: key, modelInit: SharingInvitation.init)
            
        guard case .noObjectFound = results else {
            XCTFail()
            return
        }
            
        sharingInvitationUUID = createSharingInvitation(permission: .write, sharingGroupUUID: sharingGroupUUID)
        guard sharingInvitationUUID != nil else {
            XCTFail()
            return
        }
        
        // Since the user account represented by sharingUser is already a member of the sharing group referenced by the specific sharingGroupUUID, this redeem attempt will fail.
        let result = redeemSharingInvitation(sharingUser: sharingUser, sharingInvitationUUID: sharingInvitationUUID, errorExpected: true)
        XCTAssert(result == nil)
    }
    
    func testThatRedeemingForSameSharingGroupFails() {
        redeemingForSameSharingGroupFails(sharingUser: .primarySharingAccount)
    }
    
    func checkingCredsOnASharingUserGivesSharingPermission(sharingUser: TestAccount) {
        let perm:Permission = .write
        var actualSharingGroupUUID: String?
        var newSharingUserId:UserId!
        let owningUser:TestAccount = .primaryOwningAccount
        
        createSharingUser(withSharingPermission: perm, sharingUser: sharingUser, owningUserWhenCreating: owningUser) { userId, sharingGroupUUID, _ in
            actualSharingGroupUUID = sharingGroupUUID
            newSharingUserId = userId
        }
        
        guard newSharingUserId != nil,
            actualSharingGroupUUID != nil,
            let (_, groups) = getIndex(testAccount: sharingUser) else {
            XCTFail()
            return
        }
        
        let filtered = groups.filter {$0.sharingGroupUUID == actualSharingGroupUUID}
        
        guard filtered.count == 1 else {
            XCTFail()
            return
        }
        
        checkOwingUserForSharingGroupUser(sharingGroupUUID: actualSharingGroupUUID!, sharingUserId: newSharingUserId, sharingUser: sharingUser, owningUser: owningUser)
        
        XCTAssert(filtered[0].permission == perm, "Actual: \(String(describing: filtered[0].permission)); expected: \(perm)")
    }
    
    func testThatCheckingCredsOnASharingUserGivesSharingPermission() {
        checkingCredsOnASharingUserGivesSharingPermission(sharingUser: .primarySharingAccount)
    }
    
    func testThatCheckingCredsOnARootOwningUserGivesAdminSharingPermission() {
        let deviceUUID = Foundation.UUID().uuidString
        let sharingGroupUUID = Foundation.UUID().uuidString

        guard let _ = self.addNewUser(sharingGroupUUID: sharingGroupUUID, deviceUUID:deviceUUID) else {
            XCTFail()
            return
        }
        
        guard let (_, groups) = getIndex() else {
            XCTFail()
            return
        }
        
        let filtered = groups.filter {$0.sharingGroupUUID == sharingGroupUUID}
        
        guard filtered.count == 1 else {
            XCTFail()
            return
        }
        
        XCTAssert(filtered[0].permission == .admin)
    }
    
    func testThatDeletingSharingUserWorks() {
        createSharingUser(sharingUser: .primarySharingAccount)
        
        let deviceUUID = Foundation.UUID().uuidString

        // remove
        performServerTest(testAccount: .primarySharingAccount) { expectation, creds in
            let headers = self.setupHeaders(testUser: .primarySharingAccount, accessToken: creds.accessToken, deviceUUID:deviceUUID)
            
            self.performRequest(route: ServerEndpoints.removeUser, headers: headers) { response, dict in
                Log.info("Status code: \(response!.statusCode)")
                XCTAssert(response!.statusCode == .OK, "removeUser failed")
                expectation.fulfill()
            }
        }
    }
    
    func testThatRedeemingWithAnExistingOwningAccountWorks() {
        // Create an owning user, A -- this also creates sharing group 1
        // Create another owning user, B (also creates a sharing group)
        // A creates sharing invitation to sharing group 1.
        // B redeems sharing invitation.
        
        let deviceUUID = Foundation.UUID().uuidString
        let permission:Permission = .read
        let sharingGroupUUID1 = Foundation.UUID().uuidString

        guard let _ = self.addNewUser(testAccount: .primaryOwningAccount, sharingGroupUUID: sharingGroupUUID1, deviceUUID:deviceUUID) else {
            XCTFail()
            return
        }

        let sharingGroupUUID2 = Foundation.UUID().uuidString

        guard let _ = self.addNewUser(testAccount: .secondaryOwningAccount, sharingGroupUUID: sharingGroupUUID2, deviceUUID:deviceUUID) else {
            XCTFail()
            return
        }
        
        let sharingInvitationUUID:String! = createSharingInvitation(testAccount: .primaryOwningAccount, permission: permission, sharingGroupUUID:sharingGroupUUID1)
        
        guard sharingInvitationUUID != nil else {
            XCTFail()
            return
        }

        guard let redeemResult = redeemSharingInvitation(sharingUser: .secondaryOwningAccount, sharingInvitationUUID: sharingInvitationUUID) else {
            XCTFail()
            return
        }
        
        XCTAssert(redeemResult.userId != nil && redeemResult.sharingGroupUUID != nil)
        
        checkOwingUserForSharingGroupUser(sharingGroupUUID: sharingGroupUUID1, sharingUserId: redeemResult.userId, sharingUser: .secondaryOwningAccount, owningUser: .primaryOwningAccount)
    }
    
    func testRedeemingSharingInvitationThatHasAlreadyBeenRedeemedFails() {
        let sharingUser1:TestAccount = .primarySharingAccount
        let sharingUser2:TestAccount = .secondarySharingAccount
        let owningUser:TestAccount = .primaryOwningAccount

        var sharingGroupUUID: String!
        var newSharingUserId: UserId!
        var sharingInvitationUUID: String!
        
        createSharingUser(sharingUser: sharingUser1, owningUserWhenCreating: owningUser) { userId, sid, sharingInviteUUID in
            sharingGroupUUID = sid
            newSharingUserId = userId
            sharingInvitationUUID = sharingInviteUUID
        }
        
        guard sharingGroupUUID != nil, newSharingUserId != nil else {
            XCTFail()
            return
        }
        
        let result = redeemSharingInvitation(sharingUser:sharingUser2, sharingInvitationUUID: sharingInvitationUUID, errorExpected: true)
        XCTAssert(result == nil)
    }
    
    func testTwoAcceptorsSharingInvitationCanBeRedeemedTwice() {
        let sharingUser1:TestAccount = .primarySharingAccount
        let sharingUser2:TestAccount = .secondarySharingAccount
        let owningUser:TestAccount = .primaryOwningAccount

        var sharingGroupUUID: String!
        var newSharingUserId: UserId!
        var sharingInvitationUUID: String!
        
        createSharingUser(sharingUser: sharingUser1, owningUserWhenCreating: owningUser, numberAcceptors: 2) { userId, sid, sharingInviteUUID in
            sharingGroupUUID = sid
            newSharingUserId = userId
            sharingInvitationUUID = sharingInviteUUID
        }
        
        guard sharingGroupUUID != nil, newSharingUserId != nil else {
            XCTFail()
            return
        }
        
        guard let _ = redeemSharingInvitation(sharingUser:sharingUser2, sharingInvitationUUID: sharingInvitationUUID) else {
            XCTFail()
            return
        }
        
        // Make sure the sharing invitation has now been removed.
        let key = SharingInvitationRepository.LookupKey.sharingInvitationUUID(uuid: sharingInvitationUUID)
        let results = SharingInvitationRepository(self.db).lookup(key: key, modelInit: SharingInvitation.init)
    
        guard case .noObjectFound = results else {
            XCTFail()
            return
        }
    }

    func testNonSocialSharingInvitationRedeemedSociallyFails() {
        let sharingUser:TestAccount = .nonOwningSharingAccount
        let owningUser:TestAccount = .primaryOwningAccount

        createSharingUser(sharingUser: sharingUser, owningUserWhenCreating: owningUser, allowSharingAcceptance: false, failureExpected: true) { userId, sid, sharingInviteUUID in
        }
    }

    func testNonSocialSharingInvitationRedeemedNonSociallyWorks() {
        let sharingUser:TestAccount = .secondaryOwningAccount
        let owningUser:TestAccount = .primaryOwningAccount

        createSharingUser(sharingUser: sharingUser, owningUserWhenCreating: owningUser, allowSharingAcceptance: false) { userId, sid, sharingInviteUUID in
        }
    }
}

