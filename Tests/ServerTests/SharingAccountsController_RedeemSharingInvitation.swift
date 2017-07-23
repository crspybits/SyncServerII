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
import PerfectLib
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
    
    func testThatRedeemingWithAnotherGoogleAccountWorks() {
        createSharingUser(sharingUser: .google2)
    }
    
    func testThatRedeemingWithAFacebookAccountWorks() {
        createSharingUser(sharingUser: .facebook1)
    }
    
    func redeemingASharingInvitationWithoutGivingTheInvitationUUIDFails(sharingUser: TestAccount) {
        let deviceUUID = PerfectLib.UUID().string
        self.addNewUser(deviceUUID:deviceUUID)
            
        redeemSharingInvitation(sharingUser: sharingUser, errorExpected:true) { expectation in
            expectation.fulfill()
        }
    }
    
    func testThatRedeemingASharingInvitationByAGoogleUserWithoutGivingTheInvitationUUIDFails() {
        redeemingASharingInvitationWithoutGivingTheInvitationUUIDFails(sharingUser: .google2)
    }
    
    func testThatRedeemingASharingInvitationByAFacebookUserWithoutGivingTheInvitationUUIDFails() {
        redeemingASharingInvitationWithoutGivingTheInvitationUUIDFails(sharingUser: .facebook1)
    }
    
    func testThatRedeemingWithTheSameGoogleAccountAsTheOwningAccountFails() {
        let deviceUUID = PerfectLib.UUID().string
        self.addNewUser(deviceUUID:deviceUUID)
        
        var sharingInvitationUUID:String!
        
        createSharingInvitation(permission: .read) { expectation, invitationUUID in
            sharingInvitationUUID = invitationUUID
            expectation.fulfill()
        }
        
        redeemSharingInvitation(sharingUser: .google1, sharingInvitationUUID: sharingInvitationUUID, errorExpected:true) { expectation in
            expectation.fulfill()
        }
    }
    
    func testThatRedeemingWithAnExistingOtherOwningGoogleAccountFails() {
        let deviceUUID = PerfectLib.UUID().string
        self.addNewUser(deviceUUID:deviceUUID)
        
        var sharingInvitationUUID:String!
        
        createSharingInvitation(permission: .read) { expectation, invitationUUID in
            sharingInvitationUUID = invitationUUID
            expectation.fulfill()
        }
        
        let deviceUUID2 = PerfectLib.UUID().string
        addNewUser(testAccount: .google3, deviceUUID:deviceUUID2)
        
        redeemSharingInvitation(sharingUser: .google3, sharingInvitationUUID: sharingInvitationUUID, errorExpected:true) { expectation in
            expectation.fulfill()
        }
    }
    
    func redeemingWithAnExistingOtherSharingAccountFails(sharingUser: TestAccount) {
        let deviceUUID = PerfectLib.UUID().string
        self.addNewUser(deviceUUID:deviceUUID)
            
        var sharingInvitationUUID:String!
            
        createSharingInvitation(permission: .read) { expectation, invitationUUID in
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
            
        createSharingInvitation(permission: .write) { expectation, invitationUUID in
            sharingInvitationUUID = invitationUUID
            expectation.fulfill()
        }
            
        // Since the user account represented by sharingUser has already been used to create a sharing account, this redeem attempt will fail.
        redeemSharingInvitation(sharingUser: sharingUser, sharingInvitationUUID: sharingInvitationUUID, errorExpected: true) { expectation in
            expectation.fulfill()
        }
    }
    
    func testThatRedeemingWithAnExistingSharingGoogleAccountFails() {
        redeemingWithAnExistingOtherSharingAccountFails(sharingUser: .google2)
    }
    
    func testThatRedeemingWithAnExistingSharingFacebookAccountFails() {
        redeemingWithAnExistingOtherSharingAccountFails(sharingUser: .facebook1)
    }
    
    func checkingCredsOnASharingUserGivesSharingPermission(sharingUser: TestAccount) {
        let perm:SharingPermission = .write
        createSharingUser(withSharingPermission: perm, sharingUser: sharingUser)
            
        let deviceUUID = PerfectLib.UUID().string
            
        performServerTest(testAccount: sharingUser) { expectation, testCreds in
            let tokenType = sharingUser.type.toAuthTokenType()
            let headers = self.setupHeaders(tokenType: tokenType, accessToken: testCreds.accessToken, deviceUUID:deviceUUID)
            
            self.performRequest(route: ServerEndpoints.checkCreds, headers: headers) { response, dict in
                Log.info("Status code: \(response!.statusCode)")
                XCTAssert(response!.statusCode == .OK, "checkCreds failed")
                
                let response = CheckCredsResponse(json: dict!)
                
                // This is what we're looking for: Make sure that the check creds response indicates our expected sharing permission.
                XCTAssert(response!.sharingPermission == perm)
                
                expectation.fulfill()
            }
        }
    }
    
    func testThatCheckingCredsOnAGoogleSharingUserGivesSharingPermission() {
        checkingCredsOnASharingUserGivesSharingPermission(sharingUser: .google2)
    }
    
    func testThatCheckingCredsOnAFacebookSharingUserGivesSharingPermission() {
        checkingCredsOnASharingUserGivesSharingPermission(sharingUser: .facebook1)
    }
    
    func testThatCheckingCredsOnAnOwningUserGivesNilSharingPermission() {
        let deviceUUID = PerfectLib.UUID().string
        self.addNewUser(deviceUUID:deviceUUID)
        
        performServerTest(testAccount: .google1) { expectation, googleCreds in
            let headers = self.setupHeaders(accessToken: googleCreds.accessToken, deviceUUID:deviceUUID)
            
            self.performRequest(route: ServerEndpoints.checkCreds, headers: headers) { response, dict in
                Log.info("Status code: \(response!.statusCode)")
                XCTAssert(response!.statusCode == .OK, "checkCreds failed")
                
                let response = CheckCredsResponse(json: dict!)
                
                // This is what we're looking for: Make sure that the check creds response gives nil sharing permission-- expected for an owning user.
                XCTAssert(response!.sharingPermission == nil)
                
                expectation.fulfill()
            }
        }
    }
}

extension SharingAccountsController_RedeemSharingInvitation {
    static var allTests : [(String, (SharingAccountsController_RedeemSharingInvitation) -> () throws -> Void)] {
        return [
            ("testThatRedeemingWithAnotherGoogleAccountWorks", testThatRedeemingWithAnotherGoogleAccountWorks),
            ("testThatRedeemingWithAFacebookAccountWorks", testThatRedeemingWithAFacebookAccountWorks),
            ("testThatRedeemingASharingInvitationByAGoogleUserWithoutGivingTheInvitationUUIDFails", testThatRedeemingASharingInvitationByAGoogleUserWithoutGivingTheInvitationUUIDFails),
            ("testThatRedeemingASharingInvitationByAFacebookUserWithoutGivingTheInvitationUUIDFails", testThatRedeemingASharingInvitationByAFacebookUserWithoutGivingTheInvitationUUIDFails),
            ("testThatRedeemingWithTheSameGoogleAccountAsTheOwningAccountFails", testThatRedeemingWithTheSameGoogleAccountAsTheOwningAccountFails),
            ("testThatRedeemingWithAnExistingOtherOwningGoogleAccountFails", testThatRedeemingWithAnExistingOtherOwningGoogleAccountFails),
            ("testThatRedeemingWithAnExistingSharingGoogleAccountFails", testThatRedeemingWithAnExistingSharingGoogleAccountFails),
            ("testThatRedeemingWithAnExistingSharingFacebookAccountFails", testThatRedeemingWithAnExistingSharingFacebookAccountFails),
            ("testThatCheckingCredsOnAGoogleSharingUserGivesSharingPermission", testThatCheckingCredsOnAGoogleSharingUserGivesSharingPermission),
            ("testThatCheckingCredsOnAFacebookSharingUserGivesSharingPermission", testThatCheckingCredsOnAFacebookSharingUserGivesSharingPermission),
            ("testThatCheckingCredsOnAnOwningUserGivesNilSharingPermission", testThatCheckingCredsOnAnOwningUserGivesNilSharingPermission)
        ]
    }
    
    func testLinuxTestSuiteIncludesAllTests() {
        linuxTestSuiteIncludesAllTests(testType:
            SharingAccountsController_RedeemSharingInvitation.self)
    }
}
