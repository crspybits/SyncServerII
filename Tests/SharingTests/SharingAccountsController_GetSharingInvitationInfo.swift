//
//  SharingAccountsController_GetSharingInvitationInfo.swift
//  ServerTests
//
//  Created by Christopher G Prince on 4/9/19.
//

import XCTest
@testable import Server
@testable import TestsCommon
import LoggerAPI
import Foundation
import ServerShared
import KituraNet

class SharingAccountsController_GetSharingInvitationInfo: ServerTestCase {
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
            sharingInvitationUUID = createSharingInvitation(testAccount: owningUser, permission: permission, numberAcceptors: 1, allowSharingAcceptance: allowSharingAcceptance, sharingGroupUUID:sharingGroupUUID)
            guard sharingInvitationUUID != nil else {
                XCTFail()
                return
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
        
        let permission: Permission = .admin
        let allowSharingAcceptance = true
        
        let sharingInvitationUUID:String! = createSharingInvitation(testAccount: owningUser, permission: permission, numberAcceptors: 1, allowSharingAcceptance: allowSharingAcceptance, sharingGroupUUID:sharingGroupUUID)
        guard sharingInvitationUUID != nil else {
            XCTFail()
            return
        }
        
        if hasBeenRedeemed {
            guard let _ = redeemSharingInvitation(sharingUser:sharingUser, sharingInvitationUUID: sharingInvitationUUID) else {
                XCTFail()
                return
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
        
        let permission: Permission = .admin
        let allowSharingAcceptance = true
        
        let sharingInvitationUUID:String! = createSharingInvitation(testAccount: owningUser, permission: permission, numberAcceptors: 1, allowSharingAcceptance: allowSharingAcceptance, sharingGroupUUID:sharingGroupUUID)
        
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


