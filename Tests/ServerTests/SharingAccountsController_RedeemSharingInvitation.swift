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

    // TODO: *1* With Facebook.
    /*
    func testSuccessfulRedeemingSharingInvitation() {
        // a) Create sharing invitation
        // b) Next, need to "sign out" of that account, and sign into Facebook account. Can we sign into a Facebook account purely from the server? With Google, I'm doing this using the Google refresh token. Is there something with Facebook equivalent to a refresh token?
            Not exactly, but close: Look at Long Lived Token's -- last about 60 days.
    }*/
    
    func testThatRedeemingWithASharingAccountWorks() {
        createSharingUser(sharingUser: .primarySharingAccount)
    }
    
    func redeemingASharingInvitationWithoutGivingTheInvitationUUIDFails(sharingUser: TestAccount) {
        let deviceUUID = Foundation.UUID().uuidString
        self.addNewUser(deviceUUID:deviceUUID)

        redeemSharingInvitation(sharingUser: sharingUser, errorExpected:true) { expectation in
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
        
        redeemSharingInvitation(sharingUser: .primaryOwningAccount, sharingInvitationUUID: sharingInvitationUUID, errorExpected:true) { expectation in
            expectation.fulfill()
        }
    }
    
    func testThatRedeemingWithAnExistingOtherOwningAccountFails() {
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
        
        let deviceUUID2 = Foundation.UUID().uuidString
        addNewUser(testAccount: .secondaryOwningAccount, deviceUUID:deviceUUID2)
        
        redeemSharingInvitation(sharingUser: .secondaryOwningAccount, sharingInvitationUUID: sharingInvitationUUID, errorExpected:true) { expectation in
            expectation.fulfill()
        }
    }
    
    func redeemingWithAnExistingOtherSharingAccountFails(sharingUser: TestAccount) {
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
            
        redeemSharingInvitation(sharingUser: sharingUser, sharingInvitationUUID: sharingInvitationUUID) { expectation in
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
            
        // Since the user account represented by sharingUser has already been used to create a sharing account, this redeem attempt will fail.
        redeemSharingInvitation(sharingUser: sharingUser, sharingInvitationUUID: sharingInvitationUUID, errorExpected: true) { expectation in
            expectation.fulfill()
        }
    }
    
    func testThatRedeemingWithAnExistingSharingAccountFails() {
        redeemingWithAnExistingOtherSharingAccountFails(sharingUser: .primarySharingAccount)
    }
    
    func checkingCredsOnASharingUserGivesSharingPermission(sharingUser: TestAccount) {
        let perm:Permission = .write
        createSharingUser(withSharingPermission: perm, sharingUser: sharingUser)
            
        let deviceUUID = Foundation.UUID().uuidString
            
        performServerTest(testAccount: sharingUser) { expectation, testCreds in
            let headers = self.setupHeaders(testUser:sharingUser, accessToken: testCreds.accessToken, deviceUUID:deviceUUID)
            
            self.performRequest(route: ServerEndpoints.checkCreds, headers: headers) { response, dict in
                Log.info("Status code: \(response!.statusCode)")
                XCTAssert(response!.statusCode == .OK, "checkCreds failed")
                
                let response = CheckCredsResponse(json: dict!)
                
                // This is what we're looking for: Make sure that the check creds response indicates our expected sharing permission.
                XCTAssert(response!.permission == perm)
                
                expectation.fulfill()
            }
        }
    }
    
    func testThatCheckingCredsOnASharingUserGivesSharingPermission() {
        checkingCredsOnASharingUserGivesSharingPermission(sharingUser: .primarySharingAccount)
    }
    
    func testThatCheckingCredsOnARootOwningUserGivesAdminSharingPermission() {
        let deviceUUID = Foundation.UUID().uuidString
        guard let _ = self.addNewUser(deviceUUID:deviceUUID) else {
            XCTFail()
            return
        }
        
        performServerTest(testAccount: .primaryOwningAccount) { expectation, creds in
            let headers = self.setupHeaders(testUser: .primaryOwningAccount, accessToken: creds.accessToken, deviceUUID:deviceUUID)
            
            self.performRequest(route: ServerEndpoints.checkCreds, headers: headers) { response, dict in
                Log.info("Status code: \(response!.statusCode)")
                XCTAssert(response!.statusCode == .OK, "checkCreds failed")
                
                let response = CheckCredsResponse(json: dict!)

                XCTAssert(response!.permission == .admin)
                
                expectation.fulfill()
            }
        }
    }
}

extension SharingAccountsController_RedeemSharingInvitation {
    static var allTests : [(String, (SharingAccountsController_RedeemSharingInvitation) -> () throws -> Void)] {
        return [
            ("testThatRedeemingWithASharingAccountWorks", testThatRedeemingWithASharingAccountWorks),
            ("testThatRedeemingASharingInvitationByAUserWithoutGivingTheInvitationUUIDFails", testThatRedeemingASharingInvitationByAUserWithoutGivingTheInvitationUUIDFails),
            
            ("testThatRedeemingWithTheSameAccountAsTheOwningAccountFails", testThatRedeemingWithTheSameAccountAsTheOwningAccountFails),
            
            ("testThatRedeemingWithAnExistingOtherOwningAccountFails", testThatRedeemingWithAnExistingOtherOwningAccountFails),
            ("testThatRedeemingWithAnExistingSharingAccountFails", testThatRedeemingWithAnExistingSharingAccountFails),
            
            ("testThatCheckingCredsOnASharingUserGivesSharingPermission", testThatCheckingCredsOnASharingUserGivesSharingPermission),
            
            ("testThatCheckingCredsOnARootOwningUserGivesAdminSharingPermission", testThatCheckingCredsOnARootOwningUserGivesAdminSharingPermission)
        ]
    }
    
    func testLinuxTestSuiteIncludesAllTests() {
        linuxTestSuiteIncludesAllTests(testType:
            SharingAccountsController_RedeemSharingInvitation.self)
    }
}
