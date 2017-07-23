//
//  SharingAccountsController_CreateSharingInvitation.swift
//  Server
//
//  Created by Christopher Prince on 4/11/17.
//
//

import XCTest
@testable import Server
import LoggerAPI
import PerfectLib
import Foundation
import SyncServerShared

class SharingAccountsController_CreateSharingInvitation: ServerTestCase, LinuxTestable {

    override func setUp() {
        super.setUp()
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }

    override func tearDown() {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
        super.tearDown()
    }
    
    func testSuccessfulReadSharingInvitationCreationByAnOwningUser() {
        let deviceUUID = PerfectLib.UUID().string
        self.addNewUser(deviceUUID:deviceUUID)
        self.createSharingInvitation(permission: .read) { expectation, invitationUUID in
            XCTAssert(invitationUUID != nil)
            guard let _ = UUID(uuidString: invitationUUID!) else {
                XCTFail()
                expectation.fulfill()
                return
            }
            
            expectation.fulfill()
        }
    }
    
    func testSuccessfulWriteSharingInvitationCreationByAnOwningUser() {
        let deviceUUID = PerfectLib.UUID().string
        addNewUser(deviceUUID:deviceUUID)
        createSharingInvitation(permission: .write) { expectation, invitationUUID in
            XCTAssert(invitationUUID != nil)
            guard let _ = UUID(uuidString: invitationUUID!) else {
                XCTFail()
                expectation.fulfill()
                return
            }

            expectation.fulfill()
        }
    }
    
    func sharingInvitationCreationByAnAdminSharingUser(sharingUser:TestAccount) {
        createSharingUser(withSharingPermission: .admin, sharingUser: sharingUser)
        
        // Lookup the userId for the freshly created owning user.
        let userKey = UserRepository.LookupKey.accountTypeInfo(accountType: .Google, credsId: TestAccount.google1.id())
        let userResults = UserRepository(self.db).lookup(key: userKey, modelInit: User.init)
        guard case .found(let model) = userResults,
            let owningUserId = (model as? User)?.userId else {
            XCTFail()
            return
        }
        
        var sharingInvitationUUID:String!
        
        createSharingInvitation(testAccount: sharingUser, permission: .write) { expectation, invitationUUID in
            XCTAssert(invitationUUID != nil)
            guard let _ = UUID(uuidString: invitationUUID!) else {
                XCTFail()
                expectation.fulfill()
                return
            }
            
            sharingInvitationUUID = invitationUUID
            
            expectation.fulfill()
        }
            
        // Now, who is the owning user? Let's make sure the owning user is passed along transitively. It should *not* be the id of the admin sharing user, it should be the owning user of the admin user.
            
        let key = SharingInvitationRepository.LookupKey.sharingInvitationUUID(uuid: sharingInvitationUUID)
        let results = SharingInvitationRepository(db).lookup(key: key, modelInit: SharingInvitation.init)
            
        guard case .found(let model2) = results,
            let invitation = model2 as? SharingInvitation else {
            XCTFail("ERROR: Did not find sharing invitation!")
            return
        }
            
        XCTAssert(invitation.owningUserId == owningUserId, "ERROR: invitation.owningUserId: \(invitation.owningUserId) was not equal to \(owningUserId)")
    }
    
    func testSuccessfulSharingInvitationCreationByAnAdminGoogleSharingUser() {
        sharingInvitationCreationByAnAdminSharingUser(sharingUser: .google2)
    }
    
    func testSuccessfulSharingInvitationCreationByAnAdminFacebookSharingUser() {
        sharingInvitationCreationByAnAdminSharingUser(sharingUser: .facebook1)
    }
    
    func failureOfSharingInvitationCreationByAReadSharingUser(sharingUser: TestAccount) {
        createSharingUser(withSharingPermission: .read, sharingUser: sharingUser)
            
        // The sharing user just created is that with account sharingUser. The following will fail because we're attempting to create a sharing invitation with a non-admin user. This non-admin (read) user is referenced by the sharingUser token.
            
        createSharingInvitation(testAccount: sharingUser, permission: .read, errorExpected: true) { expectation, invitationUUID in
            expectation.fulfill()
        }
    }
    
    func testFailureOfSharingInvitationCreationByAReadGoogleSharingUser() {
        failureOfSharingInvitationCreationByAReadSharingUser(sharingUser: .google2)
    }
    
    func testFailureOfSharingInvitationCreationByAReadFacebookSharingUser() {
        failureOfSharingInvitationCreationByAReadSharingUser(sharingUser: .facebook1)
    }
    
    func failureOfSharingInvitationCreationByAWriteSharingUser(sharingUser: TestAccount) {
        createSharingUser(withSharingPermission: .write, sharingUser: sharingUser)
            
        createSharingInvitation(testAccount: sharingUser, permission: .read, errorExpected: true) { expectation, invitationUUID in
            expectation.fulfill()
        }
    }
    
    func testFailureOfSharingInvitationCreationByAGoogleWriteSharingUser() {
        failureOfSharingInvitationCreationByAWriteSharingUser(sharingUser: .google2)
    }
    
    func testFailureOfSharingInvitationCreationByAFacebookWriteSharingUser() {
        failureOfSharingInvitationCreationByAWriteSharingUser(sharingUser: .facebook1)
    }
    
    func testSharingInvitationCreationFailsWithNoAuthorization() {
        self.performServerTest { expectation, googleCreds in
            let request = CreateSharingInvitationRequest(json: [
                CreateSharingInvitationRequest.sharingPermissionKey : SharingPermission.read
            ])
            
            self.performRequest(route: ServerEndpoints.createSharingInvitation, urlParameters: "?" + request!.urlParameters()!, body:nil) { response, dict in
                Log.info("Status code: \(response!.statusCode)")
                XCTAssert(response!.statusCode != .OK, "Worked with bad request!")
                expectation.fulfill()
            }
        }
    }
}

extension SharingAccountsController_CreateSharingInvitation {
    static var allTests : [(String, (SharingAccountsController_CreateSharingInvitation) -> () throws -> Void)] {
        return [
            ("testSuccessfulReadSharingInvitationCreationByAnOwningUser", testSuccessfulReadSharingInvitationCreationByAnOwningUser),
            ("testSuccessfulWriteSharingInvitationCreationByAnOwningUser", testSuccessfulWriteSharingInvitationCreationByAnOwningUser),
            ("testSuccessfulSharingInvitationCreationByAnAdminGoogleSharingUser", testSuccessfulSharingInvitationCreationByAnAdminGoogleSharingUser),
            ("testSuccessfulSharingInvitationCreationByAnAdminFacebookSharingUser", testSuccessfulSharingInvitationCreationByAnAdminFacebookSharingUser),
            ("testFailureOfSharingInvitationCreationByAReadGoogleSharingUser", testFailureOfSharingInvitationCreationByAReadGoogleSharingUser),
            ("testFailureOfSharingInvitationCreationByAReadFacebookSharingUser", testFailureOfSharingInvitationCreationByAReadFacebookSharingUser),
            ("testFailureOfSharingInvitationCreationByAGoogleWriteSharingUser", testFailureOfSharingInvitationCreationByAGoogleWriteSharingUser),
            ("testFailureOfSharingInvitationCreationByAFacebookWriteSharingUser", testFailureOfSharingInvitationCreationByAFacebookWriteSharingUser),
            ("testSharingInvitationCreationFailsWithNoAuthorization", testSharingInvitationCreationFailsWithNoAuthorization)
        ]
    }
    
    func testLinuxTestSuiteIncludesAllTests() {
        linuxTestSuiteIncludesAllTests(testType:
            SharingAccountsController_CreateSharingInvitation.self)
    }
}
