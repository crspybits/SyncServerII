//
//  SharingAccountsController_RedeemSharingInvitation.swift
//  Server
//
//  Created by Christopher Prince on 4/12/17.
//
//

import XCTest
@testable import Server
import LoggerAPI
import Foundation
import SyncServerShared

class SharingAccountsController_RedeemSharingInvitation: ServerTestCase, LinuxTestable {

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
        var sharingGroupId: SharingGroupId!
        var newSharingUserId: UserId!
        createSharingUser(sharingUser: sharingUser) { userId, sid in
            sharingGroupId = sid
            newSharingUserId = userId
        }
        
        guard sharingGroupId != nil else {
            XCTFail()
            return
        }
        
        checkOwingUserIdForSharingGroupUser(sharingGroupId: sharingGroupId, userId: newSharingUserId, sharingUser: sharingUser)
    }
    
    func testThatRedeemingUsingGoogleAccountWithoutCloudFolderNameFails() {
        let permission:Permission = .write
        let sharingUser:TestAccount = .google2

        let deviceUUID = Foundation.UUID().uuidString

        guard let addUserResponse = self.addNewUser(deviceUUID:deviceUUID),
            let sharingGroupId = addUserResponse.sharingGroupId else {
            XCTFail()
            return
        }

        var sharingInvitationUUID:String!
        
        createSharingInvitation(permission: permission, sharingGroupId:sharingGroupId) { expectation, invitationUUID in
            sharingInvitationUUID = invitationUUID
            expectation.fulfill()
        }
        
        redeemSharingInvitation(sharingUser:sharingUser, canGiveCloudFolderName: false, sharingInvitationUUID: sharingInvitationUUID, errorExpected: true) { result, expectation in
            expectation.fulfill()
        }
    }
        
    func redeemingASharingInvitationWithoutGivingTheInvitationUUIDFails(sharingUser: TestAccount) {
        let deviceUUID = Foundation.UUID().uuidString

        guard let _ = self.addNewUser(deviceUUID:deviceUUID) else {
            XCTFail()
            return
        }

        redeemSharingInvitation(sharingUser: sharingUser, errorExpected:true) { _, expectation in
            expectation.fulfill()
        }
    }
    
    func testThatRedeemingASharingInvitationByAUserWithoutGivingTheInvitationUUIDFails() {
        redeemingASharingInvitationWithoutGivingTheInvitationUUIDFails(sharingUser:
            .primarySharingAccount)
    }

    func testThatRedeemingWithTheSameAccountAsTheOwningAccountFails() {
        let deviceUUID = Foundation.UUID().uuidString
        guard let addUserResponse = self.addNewUser(deviceUUID:deviceUUID),
            let sharingGroupId = addUserResponse.sharingGroupId else {
            XCTFail()
            return
        }
        
        var sharingInvitationUUID:String!
        
        createSharingInvitation(permission: .read, sharingGroupId: sharingGroupId) { expectation, invitationUUID in
            sharingInvitationUUID = invitationUUID
            expectation.fulfill()
        }
        
        redeemSharingInvitation(sharingUser: .primaryOwningAccount, sharingInvitationUUID: sharingInvitationUUID, errorExpected:true) { _, expectation in
            expectation.fulfill()
        }
    }
    
    // 8/12/18; This now works-- i.e., you can redeem with other owning accounts-- because each user can now be in multiple sharing groups. (Prior to this, it was a failure test!).
    func testThatRedeemingWithAnExistingOtherOwningAccountWorks() {
        let deviceUUID = Foundation.UUID().uuidString
        
        guard let addUserResponse = self.addNewUser(deviceUUID:deviceUUID),
            let sharingGroupId = addUserResponse.sharingGroupId else {
            XCTFail()
            return
        }
        
        var sharingInvitationUUID:String!
        
        createSharingInvitation(permission: .read, sharingGroupId:sharingGroupId) { expectation, invitationUUID in
            sharingInvitationUUID = invitationUUID
            expectation.fulfill()
        }
        
        let owningAccount:TestAccount = .secondaryOwningAccount
        let deviceUUID2 = Foundation.UUID().uuidString
        addNewUser(testAccount: owningAccount, deviceUUID:deviceUUID2)
        
        var result: RedeemSharingInvitationResponse!
        redeemSharingInvitation(sharingUser: owningAccount, sharingInvitationUUID: sharingInvitationUUID) { response, expectation in
            result = response
            expectation.fulfill()
        }
        
        guard result != nil else {
            XCTFail()
            return
        }
        
        checkOwingUserIdForSharingGroupUser(sharingGroupId: sharingGroupId, userId: result.userId, sharingUser: owningAccount)
    }
    
    // Redeem sharing invitation for existing user: Works if user isn't already in sharing group
    func testThatRedeemingWithAnExistingOtherSharingAccountWorks() {
        redeemWithAnExistingOtherSharingAccount()
    }
    
    func redeemingForSameSharingGroupFails(sharingUser: TestAccount) {
        let deviceUUID = Foundation.UUID().uuidString
        
        guard let addUserResponse = self.addNewUser(deviceUUID:deviceUUID),
            let sharingGroupId = addUserResponse.sharingGroupId else {
            XCTFail()
            return
        }
            
        var sharingInvitationUUID:String!
            
        createSharingInvitation(permission: .read, sharingGroupId: sharingGroupId) { expectation, invitationUUID in
            sharingInvitationUUID = invitationUUID
            expectation.fulfill()
        }
            
        redeemSharingInvitation(sharingUser: sharingUser, sharingInvitationUUID: sharingInvitationUUID) { _, expectation in
            expectation.fulfill()
        }
            
        // Check to make sure we have a new user:
        let userKey = UserRepository.LookupKey.accountTypeInfo(accountType: sharingUser.type, credsId: sharingUser.id())
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
            
        createSharingInvitation(permission: .write, sharingGroupId: sharingGroupId) { expectation, invitationUUID in
            sharingInvitationUUID = invitationUUID
            expectation.fulfill()
        }
            
        // Since the user account represented by sharingUser is already a member of the sharing group referenced by the specific sharingGroupId, this redeem attempt will fail.
        redeemSharingInvitation(sharingUser: sharingUser, sharingInvitationUUID: sharingInvitationUUID, errorExpected: true) { _, expectation in
            expectation.fulfill()
        }
    }
    
    func testThatRedeemingForSameSharingGroupFails() {
        redeemingForSameSharingGroupFails(sharingUser: .primarySharingAccount)
    }
    
    func checkingCredsOnASharingUserGivesSharingPermission(sharingUser: TestAccount) {
        let perm:Permission = .write
        var actualSharingGroupId: SharingGroupId?
        createSharingUser(withSharingPermission: perm, sharingUser: sharingUser) { _, sharingGroupId in
            actualSharingGroupId = sharingGroupId
        }
        
        guard let (_, groups) = getIndex(testAccount: sharingUser) else {
            XCTFail()
            return
        }
        
        let filtered = groups.filter {$0.sharingGroupId == actualSharingGroupId}
        
        guard filtered.count == 1 else {
            XCTFail()
            return
        }
        
        
        XCTAssert(filtered[0].permission == perm, "Actual: \(String(describing: filtered[0].permission)); expected: \(perm)")
    }
    
    func testThatCheckingCredsOnASharingUserGivesSharingPermission() {
        checkingCredsOnASharingUserGivesSharingPermission(sharingUser: .primarySharingAccount)
    }
    
    func testThatCheckingCredsOnARootOwningUserGivesAdminSharingPermission() {
        let deviceUUID = Foundation.UUID().uuidString
        guard let response = self.addNewUser(deviceUUID:deviceUUID),
            let sharingGroupId = response.sharingGroupId else {
            XCTFail()
            return
        }
        
        guard let (_, groups) = getIndex() else {
            XCTFail()
            return
        }
        
        let filtered = groups.filter {$0.sharingGroupId == sharingGroupId}
        
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

        guard let addUserResponse1 = self.addNewUser(testAccount: .primaryOwningAccount, deviceUUID:deviceUUID),
            let sharingGroupId = addUserResponse1.sharingGroupId else {
            XCTFail()
            return
        }

        guard let _ = self.addNewUser(testAccount: .secondaryOwningAccount, deviceUUID:deviceUUID) else {
            XCTFail()
            return
        }
        
        var sharingInvitationUUID:String!
        
        createSharingInvitation(testAccount: .primaryOwningAccount, permission: permission, sharingGroupId:sharingGroupId) { expectation, invitationUUID in
            sharingInvitationUUID = invitationUUID
            expectation.fulfill()
        }
        
        redeemSharingInvitation(sharingUser: .secondaryOwningAccount, sharingInvitationUUID: sharingInvitationUUID) { result, expectation in
            XCTAssert(result?.userId != nil && result?.sharingGroupId != nil)
            expectation.fulfill()
        }
    }
}

extension SharingAccountsController_RedeemSharingInvitation {
    static var allTests : [(String, (SharingAccountsController_RedeemSharingInvitation) -> () throws -> Void)] {
        return [
            ("testThatRedeemingWithASharingAccountWorks", testThatRedeemingWithASharingAccountWorks),
            
            ("testThatRedeemingUsingGoogleAccountWithoutCloudFolderNameFails",
                testThatRedeemingUsingGoogleAccountWithoutCloudFolderNameFails),
            
            ("testThatRedeemingASharingInvitationByAUserWithoutGivingTheInvitationUUIDFails", testThatRedeemingASharingInvitationByAUserWithoutGivingTheInvitationUUIDFails),
            
            ("testThatRedeemingWithTheSameAccountAsTheOwningAccountFails", testThatRedeemingWithTheSameAccountAsTheOwningAccountFails),
            
            ("testThatRedeemingWithAnExistingOtherOwningAccountWorks", testThatRedeemingWithAnExistingOtherOwningAccountWorks),
            
            ("testThatRedeemingWithAnExistingOtherSharingAccountWorks", testThatRedeemingWithAnExistingOtherSharingAccountWorks),
            
            ("testThatRedeemingForSameSharingGroupFails", testThatRedeemingForSameSharingGroupFails),
            
            ("testThatCheckingCredsOnASharingUserGivesSharingPermission", testThatCheckingCredsOnASharingUserGivesSharingPermission),
            
            ("testThatCheckingCredsOnARootOwningUserGivesAdminSharingPermission", testThatCheckingCredsOnARootOwningUserGivesAdminSharingPermission),
            
            ("testThatDeletingSharingUserWorks", testThatDeletingSharingUserWorks),
            
            ("testThatRedeemingWithAnExistingOwningAccountWorks", testThatRedeemingWithAnExistingOwningAccountWorks)
        ]
    }
    
    func testLinuxTestSuiteIncludesAllTests() {
        linuxTestSuiteIncludesAllTests(testType:
            SharingAccountsController_RedeemSharingInvitation.self)
    }
}
