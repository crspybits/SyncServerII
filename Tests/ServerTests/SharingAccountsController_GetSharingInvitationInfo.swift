//
//  SharingAccountsController_GetSharingInvitationInfo.swift
//  ServerTests
//
//  Created by Christopher G Prince on 4/9/19.
//

import XCTest
@testable import Server
import LoggerAPI
import Foundation
import SyncServerShared
import KituraNet

class SharingAccountsController_GetSharingInvitationInfo: ServerTestCase, LinuxTestable {
    override func setUp() {
        super.setUp()
    }

    override func tearDown() {
        super.tearDown()
    }
    
    func getSharingInfo(existing: Bool) {
        var httpStatusCodeExpected: HTTPStatusCode = .OK
        if !existing {
            httpStatusCodeExpected = .gone
        }
    
        let owningUser:TestAccount = .primaryOwningAccount
        
        let sharingGroupUUID = Foundation.UUID().uuidString
        let deviceUUID = Foundation.UUID().uuidString
        guard let _ = self.addNewUser(testAccount: owningUser, sharingGroupUUID: sharingGroupUUID, deviceUUID:deviceUUID) else {
            XCTFail()
            return
        }

        var sharingInvitationUUID:String!
        
        let permission: Permission = .read
        let allowSharingAcceptance = false
        
        if existing {
            createSharingInvitation(testAccount: owningUser, permission: permission, numberAcceptors: 1, allowSharingAcceptance: allowSharingAcceptance, sharingGroupUUID:sharingGroupUUID) { expectation, invitationUUID in
                sharingInvitationUUID = invitationUUID
                expectation.fulfill()
            }
        }
        else {
            // Fake one!
            sharingInvitationUUID = Foundation.UUID().uuidString
        }
        
        var errorExpected = false
        if !existing {
            errorExpected = true
        }
        
        let response = getSharingInvitationInfo(sharingInvitationUUID: sharingInvitationUUID, errorExpected: errorExpected, httpStatusCodeExpected: httpStatusCodeExpected)
        if errorExpected {
            XCTAssert(response == nil)
        }
        else {
            guard let response = response else {
                XCTFail()
                return
            }
            
            XCTAssert(response.allowSocialAcceptance == allowSharingAcceptance)
            XCTAssert(response.permission == permission)
        }
    }
    
    func testNonExistentSharingInvitationUUID() {
        getSharingInfo(existing: false)
    }
    
    func testExistingSharingInvitationUUID() {
        getSharingInfo(existing: true)
    }
    
    func getSharingInfo(hasBeenRedeemed: Bool, httpStatusCodeExpected: HTTPStatusCode = .OK) {
        let sharingUser:TestAccount = .primarySharingAccount
        let owningUser:TestAccount = .primaryOwningAccount
        
        let sharingGroupUUID = Foundation.UUID().uuidString
        let deviceUUID = Foundation.UUID().uuidString
        guard let _ = self.addNewUser(testAccount: owningUser, sharingGroupUUID: sharingGroupUUID, deviceUUID:deviceUUID) else {
            XCTFail()
            return
        }

        var sharingInvitationUUID:String!
        
        let permission: Permission = .admin
        let allowSharingAcceptance = true
        
        createSharingInvitation(testAccount: owningUser, permission: permission, numberAcceptors: 1, allowSharingAcceptance: allowSharingAcceptance, sharingGroupUUID:sharingGroupUUID) { expectation, invitationUUID in
            sharingInvitationUUID = invitationUUID
            expectation.fulfill()
        }
        
        if hasBeenRedeemed {
            redeemSharingInvitation(sharingUser:sharingUser, sharingInvitationUUID: sharingInvitationUUID) { result, expectation in
                expectation.fulfill()
            }
        }
        
        let response = getSharingInvitationInfo(sharingInvitationUUID: sharingInvitationUUID, errorExpected: hasBeenRedeemed, httpStatusCodeExpected: httpStatusCodeExpected)
        if hasBeenRedeemed {
            XCTAssert(response == nil)
        }
        else {
            guard let response = response else {
                XCTFail()
                return
            }
            
            XCTAssert(response.allowSocialAcceptance == allowSharingAcceptance)
            XCTAssert(response.permission == permission)
        }
    }
    
    func testGetSharingInvitationInfoThatHasNotBeenRedeemedWorks() {
        getSharingInfo(hasBeenRedeemed: false)
    }
        
    func testGetSharingInvitationInfoThatHasAlreadyBeenRedeemedFails() {
        getSharingInfo(hasBeenRedeemed: true, httpStatusCodeExpected: .gone)
    }
    
    func testGetSharingInvitationInfoWithSecondaryAuthWorks() {
        let owningUser:TestAccount = .primaryOwningAccount
        
        let sharingGroupUUID = Foundation.UUID().uuidString
        let deviceUUID = Foundation.UUID().uuidString
        guard let _ = self.addNewUser(testAccount: owningUser, sharingGroupUUID: sharingGroupUUID, deviceUUID:deviceUUID) else {
            XCTFail()
            return
        }

        var sharingInvitationUUID:String!
        
        let permission: Permission = .admin
        let allowSharingAcceptance = true
        
        createSharingInvitation(testAccount: owningUser, permission: permission, numberAcceptors: 1, allowSharingAcceptance: allowSharingAcceptance, sharingGroupUUID:sharingGroupUUID) { expectation, invitationUUID in
            sharingInvitationUUID = invitationUUID
            expectation.fulfill()
        }
        
        guard sharingInvitationUUID != nil else {
            XCTFail()
            return
        }
        
        var response: GetSharingInvitationInfoResponse!
        
        getSharingInvitationInfoWithSecondaryAuth(testAccount: owningUser, sharingInvitationUUID: sharingInvitationUUID) { r, exp in
            response = r
            exp.fulfill()
        }
        
        guard response != nil else {
            XCTFail()
            return
        }
        
        XCTAssert(response.allowSocialAcceptance == allowSharingAcceptance)
        XCTAssert(response.permission == permission)
    }
}

extension SharingAccountsController_GetSharingInvitationInfo {
    static var allTests : [(String, (SharingAccountsController_GetSharingInvitationInfo) -> () throws -> Void)] {
        return [
            ("testNonExistentSharingInvitationUUID", testNonExistentSharingInvitationUUID),
            ("testExistingSharingInvitationUUID", testExistingSharingInvitationUUID),
            ("testGetSharingInvitationInfoThatHasNotBeenRedeemedWorks", testGetSharingInvitationInfoThatHasNotBeenRedeemedWorks),
            ("testGetSharingInvitationInfoThatHasAlreadyBeenRedeemedFails", testGetSharingInvitationInfoThatHasAlreadyBeenRedeemedFails),
            ("testGetSharingInvitationInfoWithSecondaryAuthWorks", testGetSharingInvitationInfoWithSecondaryAuthWorks)
        ]
    }
    
    func testLinuxTestSuiteIncludesAllTests() {
        linuxTestSuiteIncludesAllTests(testType:
            SharingAccountsController_GetSharingInvitationInfo.self)
    }
}

