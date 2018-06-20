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
import Foundation
import SyncServerShared

// You can run this with primarySharingAccount set to any account that allows sharing.
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
        let deviceUUID = Foundation.UUID().uuidString
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
        let deviceUUID = Foundation.UUID().uuidString
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
    
    func sharingInvitationCreationByAnAdminSharingUser(sharingUser:TestAccount, failureExpected: Bool = false) {
        // .primaryOwningAccount owning user is created as part of this.
        let testAccount:TestAccount = .primaryOwningAccount
        createSharingUser(withSharingPermission: .admin, sharingUser: sharingUser)
        
        // Lookup the userId for the freshly created owning user.
        
        let userKey = UserRepository.LookupKey.accountTypeInfo(accountType: testAccount.type, credsId: testAccount.id())
        let userResults = UserRepository(self.db).lookup(key: userKey, modelInit: User.init)
        guard case .found(let model) = userResults,
            let owningUserId = (model as? User)?.userId else {
            XCTFail()
            return
        }
        
        var sharingInvitationUUID:String!
        
        createSharingInvitation(testAccount: sharingUser, permission: .write, errorExpected: false) { expectation, invitationUUID in
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
    
    func testSuccessfulSharingInvitationCreationByAnAdminSharingUser() {
        sharingInvitationCreationByAnAdminSharingUser(sharingUser: .primarySharingAccount)
    }
    
    func failureOfSharingInvitationCreationByAReadSharingUser(sharingUser: TestAccount) {
        createSharingUser(withSharingPermission: .read, sharingUser: sharingUser)
            
        // The sharing user just created is that with account sharingUser. The following will fail because we're attempting to create a sharing invitation with a non-admin user. This non-admin (read) user is referenced by the sharingUser token.
            
        createSharingInvitation(testAccount: sharingUser, permission: .read, errorExpected: true) { expectation, invitationUUID in
            expectation.fulfill()
        }
    }
    
    func testFailureOfSharingInvitationCreationByAReadSharingUser() {
        failureOfSharingInvitationCreationByAReadSharingUser(sharingUser: .primarySharingAccount)
    }
    
    func failureOfSharingInvitationCreationByAWriteSharingUser(sharingUser: TestAccount) {
        createSharingUser(withSharingPermission: .write, sharingUser: sharingUser)
            
        createSharingInvitation(testAccount: sharingUser, permission: .read, errorExpected: true) { expectation, invitationUUID in
            expectation.fulfill()
        }
    }
    
    func testFailureOfSharingInvitationCreationByAWriteSharingUser() {
        failureOfSharingInvitationCreationByAWriteSharingUser(sharingUser: .primarySharingAccount)
    }
    
    func testSharingInvitationCreationFailsWithNoAuthorization() {
        self.performServerTest { expectation, creds in
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
    
            ("testSuccessfulSharingInvitationCreationByAnAdminSharingUser", testSuccessfulSharingInvitationCreationByAnAdminSharingUser),
            
            ("testFailureOfSharingInvitationCreationByAReadSharingUser", testFailureOfSharingInvitationCreationByAReadSharingUser),
            
            ("testFailureOfSharingInvitationCreationByAWriteSharingUser", testFailureOfSharingInvitationCreationByAWriteSharingUser),
            
            ("testSharingInvitationCreationFailsWithNoAuthorization", testSharingInvitationCreationFailsWithNoAuthorization)
        ]
    }
    
    func testLinuxTestSuiteIncludesAllTests() {
        linuxTestSuiteIncludesAllTests(testType:
            SharingAccountsController_CreateSharingInvitation.self)
    }
}
