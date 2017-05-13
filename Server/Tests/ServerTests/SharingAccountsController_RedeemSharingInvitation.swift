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

class SharingAccountsController_RedeemSharingInvitation: ServerTestCase {

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
        createSharingUser()
    }
    
    func testThatRedeemingASharingInvitationWithoutGivingTheInvitationUUIDFails() {
        let deviceUUID = PerfectLib.UUID().string
        self.addNewUser(deviceUUID:deviceUUID)
        
        redeemSharingInvitation(token: .googleRefreshToken2, errorExpected:true) { expectation in
            expectation.fulfill()
        }
    }
    
    func testThatRedeemingWithTheSameGoogleAccountAsTheOwningAccountFails() {
        let deviceUUID = PerfectLib.UUID().string
        self.addNewUser(deviceUUID:deviceUUID)
        
        var sharingInvitationUUID:String!
        
        createSharingInvitation(permission: .read) { expectation, invitationUUID in
            sharingInvitationUUID = invitationUUID
            expectation.fulfill()
        }
        
        redeemSharingInvitation(token: .googleRefreshToken1, sharingInvitationUUID: sharingInvitationUUID, errorExpected:true) { expectation in
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
        addNewUser(token:.googleRefreshToken3, deviceUUID:deviceUUID2)
        
        redeemSharingInvitation(token: .googleRefreshToken3, sharingInvitationUUID: sharingInvitationUUID, errorExpected:true) { expectation in
            expectation.fulfill()
        }
    }
    
    func testThatRedeemingWithAnExistingOtherSharingGoogleAccountFails() {
        let deviceUUID = PerfectLib.UUID().string
        self.addNewUser(deviceUUID:deviceUUID)
        
        var sharingInvitationUUID:String!
        
        createSharingInvitation(permission: .read) { expectation, invitationUUID in
            sharingInvitationUUID = invitationUUID
            expectation.fulfill()
        }
        
        redeemSharingInvitation(token: .googleRefreshToken2, sharingInvitationUUID: sharingInvitationUUID) { expectation in
            expectation.fulfill()
        }

        // Check to make sure we have a new user:
        let googleSub2 = credentialsToken(token: .googleSub2)
        let userKey = UserRepository.LookupKey.accountTypeInfo(accountType: .Google, credsId: googleSub2)
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
        
        // Since the user account represented by googleRefreshToken2 has already been used to create a sharing account, this redeem attempt will fail.
        redeemSharingInvitation(token: .googleRefreshToken2, sharingInvitationUUID: sharingInvitationUUID, errorExpected: true) { expectation in
            expectation.fulfill()
        }
    }
    
    func testThatCheckingCredsOnASharingUserGivesSharingPermission() {
        let perm:SharingPermission = .write
        createSharingUser(withSharingPermission: perm)
        
        let deviceUUID = PerfectLib.UUID().string

        performServerTest(token:.googleRefreshToken2) { expectation, googleCreds in
            let headers = self.setupHeaders(accessToken: googleCreds.accessToken, deviceUUID:deviceUUID)
            
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
    
    func testThatCheckingCredsOnAnOwningUserGivesNilSharingPermission() {
        let deviceUUID = PerfectLib.UUID().string
        self.addNewUser(deviceUUID:deviceUUID)
        
        performServerTest(token: .googleRefreshToken1) { expectation, googleCreds in
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
            ("testThatRedeemingASharingInvitationWithoutGivingTheInvitationUUIDFails", testThatRedeemingASharingInvitationWithoutGivingTheInvitationUUIDFails),
            ("testThatRedeemingWithTheSameGoogleAccountAsTheOwningAccountFails", testThatRedeemingWithTheSameGoogleAccountAsTheOwningAccountFails),
            ("testThatRedeemingWithAnExistingOtherOwningGoogleAccountFails", testThatRedeemingWithAnExistingOtherOwningGoogleAccountFails),
            ("testThatRedeemingWithAnExistingOtherSharingGoogleAccountFails", testThatRedeemingWithAnExistingOtherSharingGoogleAccountFails),
            ("testThatCheckingCredsOnASharingUserGivesSharingPermission", testThatCheckingCredsOnASharingUserGivesSharingPermission),
            ("testThatCheckingCredsOnAnOwningUserGivesNilSharingPermission", testThatCheckingCredsOnAnOwningUserGivesNilSharingPermission)
        ]
    }
}
