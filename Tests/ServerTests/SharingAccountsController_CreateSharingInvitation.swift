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
        guard let addUserResponse = self.addNewUser(deviceUUID:deviceUUID),
            let sharingGroupId = addUserResponse.sharingGroupId else {
            XCTFail()
            return
        }
        
        self.createSharingInvitation(permission: .read, sharingGroupId:sharingGroupId) { expectation, invitationUUID in
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
        
        guard let addUserResponse = self.addNewUser(deviceUUID:deviceUUID),
            let sharingGroupId = addUserResponse.sharingGroupId else {
            XCTFail()
            return
        }
        
        createSharingInvitation(permission: .write, sharingGroupId:sharingGroupId) { expectation, invitationUUID in
            XCTAssert(invitationUUID != nil)
            guard let _ = UUID(uuidString: invitationUUID!) else {
                XCTFail()
                expectation.fulfill()
                return
            }

            expectation.fulfill()
        }
    }

    func testSuccessfulAdminSharingInvitationCreationByAnOwningUser() {
        let deviceUUID = Foundation.UUID().uuidString
        
        guard let addUserResponse = self.addNewUser(deviceUUID:deviceUUID),
            let sharingGroupId = addUserResponse.sharingGroupId else {
            XCTFail()
            return
        }
        
        createSharingInvitation(permission: .admin, sharingGroupId:sharingGroupId) { expectation, invitationUUID in
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
        var actualSharingGroupId: SharingGroupId!
        
        var adminUserId:UserId!
        
        createSharingUser(withSharingPermission: .admin, sharingUser: sharingUser) { userId, sharingGroupId in
            actualSharingGroupId = sharingGroupId
            adminUserId = userId
        }
        
        guard actualSharingGroupId != nil else {
            XCTFail()
            return
        }
        
        // Lookup the userId for the freshly created owning user.
        
        let userKey = UserRepository.LookupKey.accountTypeInfo(accountType: testAccount.type, credsId: testAccount.id())
        let userResults = UserRepository(self.db).lookup(key: userKey, modelInit: User.init)
        guard case .found(let model) = userResults,
            let testAccountUserId = (model as? User)?.userId else {
            XCTFail()
            return
        }
        
        var sharingInvitationUUID:String!
        
        createSharingInvitation(testAccount: sharingUser, permission: .write, sharingGroupId: actualSharingGroupId, errorExpected: false) { expectation, invitationUUID in
            XCTAssert(invitationUUID != nil)
            guard let _ = UUID(uuidString: invitationUUID!) else {
                XCTFail()
                expectation.fulfill()
                return
            }
            
            sharingInvitationUUID = invitationUUID
            
            expectation.fulfill()
        }
            
        // Now, who is the owning user?
        // If the admin sharing user is an owning user, then the owning user of the invitation will be the admin sharing user.
        // If the admin sharing user is a sharing user, then the owning user will be the owning user (inviter) of the admin user.
            
        let key = SharingInvitationRepository.LookupKey.sharingInvitationUUID(uuid: sharingInvitationUUID)
        let results = SharingInvitationRepository(db).lookup(key: key, modelInit: SharingInvitation.init)
            
        guard case .found(let model2) = results,
            let invitation = model2 as? SharingInvitation else {
            XCTFail("ERROR: Did not find sharing invitation!")
            return
        }
        
        switch sharingUser.type.userType {
        case .owning:
            XCTAssert(invitation.owningUserId == adminUserId)
        case .sharing:
            XCTAssert(invitation.owningUserId == testAccountUserId, "ERROR: invitation.owningUserId: \(invitation.owningUserId) was not equal to \(testAccountUserId)")
        }
    }
    
    func testSuccessfulSharingInvitationCreationByAnAdminSharingUser() {
        sharingInvitationCreationByAnAdminSharingUser(sharingUser: .primarySharingAccount)
    }
    
    func failureOfSharingInvitationCreationByAReadSharingUser(sharingUser: TestAccount) {
        var actualSharingGroupId: SharingGroupId!
        createSharingUser(withSharingPermission: .read, sharingUser: sharingUser) { userId, sharingGroupId in
            actualSharingGroupId = sharingGroupId
        }
        
        guard actualSharingGroupId != nil else {
            XCTFail()
            return
        }
            
        // The sharing user just created is that with account sharingUser. The following will fail because we're attempting to create a sharing invitation with a non-admin user. This non-admin (read) user is referenced by the sharingUser token.
            
        createSharingInvitation(testAccount: sharingUser, permission: .read, sharingGroupId: actualSharingGroupId, errorExpected: true) { expectation, invitationUUID in
            expectation.fulfill()
        }
    }
    
    func testFailureOfSharingInvitationCreationByAReadSharingUser() {
        failureOfSharingInvitationCreationByAReadSharingUser(sharingUser: .primarySharingAccount)
    }
    
    func failureOfSharingInvitationCreationByAWriteSharingUser(sharingUser: TestAccount) {
        var actualSharingGroupId: SharingGroupId!
        createSharingUser(withSharingPermission: .write, sharingUser: sharingUser) { userId, sharingGroupId in
            actualSharingGroupId = sharingGroupId
        }
        
        guard actualSharingGroupId != nil else {
            XCTFail()
            return
        }
            
        createSharingInvitation(testAccount: sharingUser, permission: .read, sharingGroupId:actualSharingGroupId, errorExpected: true) { expectation, invitationUUID in
            expectation.fulfill()
        }
    }
    
    func testFailureOfSharingInvitationCreationByAWriteSharingUser() {
        failureOfSharingInvitationCreationByAWriteSharingUser(sharingUser: .primarySharingAccount)
    }
    
    func testSharingInvitationCreationFailsWithNoAuthorization() {
        self.performServerTest { expectation, creds in
            let request = CreateSharingInvitationRequest(json: [
                CreateSharingInvitationRequest.permissionKey : Permission.read,
                // A fake sharing group id. This shouldn't be the issue that fails the request. It should fail because there is no authorization.
                ServerEndpoint.sharingGroupIdKey: 0
            ])
            
            self.performRequest(route: ServerEndpoints.createSharingInvitation, urlParameters: "?" + request!.urlParameters()!, body:nil) { response, dict in
                Log.info("Status code: \(response!.statusCode)")
                XCTAssert(response!.statusCode != .OK, "Worked with bad request!")
                expectation.fulfill()
            }
        }
    }
    
    func testSharingInvitationCreationFailsWithoutMembershipInSharingGroup() {
        let deviceUUID1 = Foundation.UUID().uuidString
        guard let addUserResponse = self.addNewUser(deviceUUID:deviceUUID1),
            let sharingGroupId = addUserResponse.sharingGroupId else {
            XCTFail()
            return
        }
        
        let deviceUUID2 = Foundation.UUID().uuidString
        guard let _ = self.addNewUser(testAccount: .secondaryOwningAccount, deviceUUID:deviceUUID2) else {
            XCTFail()
            return
        }
        
        createSharingInvitation(testAccount: .secondaryOwningAccount, permission: .write, sharingGroupId:sharingGroupId, errorExpected: true) { expectation, invitationUUID in
            expectation.fulfill()
        }
    }
}

extension SharingAccountsController_CreateSharingInvitation {
    static var allTests : [(String, (SharingAccountsController_CreateSharingInvitation) -> () throws -> Void)] {
        return [
            ("testSuccessfulReadSharingInvitationCreationByAnOwningUser", testSuccessfulReadSharingInvitationCreationByAnOwningUser),
            ("testSuccessfulWriteSharingInvitationCreationByAnOwningUser", testSuccessfulWriteSharingInvitationCreationByAnOwningUser),
            ("testSuccessfulAdminSharingInvitationCreationByAnOwningUser", testSuccessfulAdminSharingInvitationCreationByAnOwningUser),
            ("testSuccessfulSharingInvitationCreationByAnAdminSharingUser", testSuccessfulSharingInvitationCreationByAnAdminSharingUser),
            ("testFailureOfSharingInvitationCreationByAReadSharingUser", testFailureOfSharingInvitationCreationByAReadSharingUser),
            ("testFailureOfSharingInvitationCreationByAWriteSharingUser", testFailureOfSharingInvitationCreationByAWriteSharingUser),
            ("testSharingInvitationCreationFailsWithNoAuthorization", testSharingInvitationCreationFailsWithNoAuthorization),
            ("testSharingInvitationCreationFailsWithoutMembershipInSharingGroup", testSharingInvitationCreationFailsWithoutMembershipInSharingGroup)
        ]
    }
    
    func testLinuxTestSuiteIncludesAllTests() {
        linuxTestSuiteIncludesAllTests(testType:
            SharingAccountsController_CreateSharingInvitation.self)
    }
}
