//
//  SpecificDatabaseTests_SharingInvitationRepository.swift
//  Server
//
//  Created by Christopher Prince on 4/10/17.
//
//

import XCTest
@testable import Server
@testable import TestsCommon
import Foundation
import Dispatch
import ServerShared

class SpecificDatabaseTests_SharingInvitationRepository: ServerTestCase {

    override func setUp() {
        super.setUp()
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }
    
    override func tearDown() {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
        super.tearDown()
    }

    func testAddingSharingInvitation() {
        let sharingGroupUUID = UUID().uuidString

        guard case .success = SharingGroupRepository(db).add(sharingGroupUUID: sharingGroupUUID) else {
            XCTFail()
            return
        }
        
        let userId:UserId = 100
        let result = SharingInvitationRepository(db).add(owningUserId: userId, sharingGroupUUID: sharingGroupUUID, permission: .read, allowSocialAcceptance: true, numberAcceptors: 2)

        guard case .success(let uuid) = result else {
            XCTFail()
            return
        }

        let key = SharingInvitationRepository.LookupKey.sharingInvitationUUID(uuid: uuid)
        let results = SharingInvitationRepository(db).lookup(key: key, modelInit: SharingInvitation.init)

        guard case .found(let model) = results else {
            XCTFail()
            return
        }

        guard let invitation = model as? SharingInvitation else {
            XCTFail()
            return
        }

        XCTAssert(invitation.owningUserId == userId)
        XCTAssert(invitation.permission == .read)
        XCTAssert(invitation.sharingInvitationUUID == uuid)
        XCTAssert(invitation.numberAcceptors == 2)
        XCTAssert(invitation.allowSocialAcceptance == true)
    }
    
    func testAttemptToRemoveStaleInvitationsThatAreNotStale() {
        let sharingGroupUUID = UUID().uuidString

        guard case .success = SharingGroupRepository(db).add(sharingGroupUUID: sharingGroupUUID) else {
            XCTFail()
            return
        }
        
        let userId:UserId = 100
        let result = SharingInvitationRepository(db).add(owningUserId: userId, sharingGroupUUID: sharingGroupUUID, permission: .write, allowSocialAcceptance: false, numberAcceptors: 1)
        
        guard case .success(let uuid) = result else {
            XCTFail()
            return
        }
        
        let exp = expectation(description: "attemptedToRemoveStateInvitation")
        
        let timer = DispatchSource.makeTimerSource()
        timer.setEventHandler() {
            let key1 = SharingInvitationRepository.LookupKey.staleExpiryDates
            let removalResult = SharingInvitationRepository(self.db).remove(key: key1)
            
            guard case .removed(numberRows:let number) = removalResult else{
                XCTFail()
                exp.fulfill()
                return
            }
            
            // We didn't remove any rows.
            XCTAssert(number == 0)

            let key2 = SharingInvitationRepository.LookupKey.sharingInvitationUUID(uuid: uuid)
            let results = SharingInvitationRepository(self.db).lookup(key: key2, modelInit: SharingInvitation.init)
            
            guard case .found(let model) = results else {
                XCTFail()
                return
            }
            
            guard let invitation = model as? SharingInvitation else {
                XCTFail()
                return
            }
            
            XCTAssert(invitation.owningUserId == userId)
            XCTAssert(invitation.permission == .write)
            XCTAssert(invitation.sharingInvitationUUID == uuid)
            XCTAssert(invitation.sharingGroupUUID == sharingGroupUUID)
            XCTAssert(invitation.numberAcceptors == 1)
            XCTAssert(invitation.allowSocialAcceptance == false)
            
            exp.fulfill()
        }
        
        let now = DispatchTime.now()
        let delayInSeconds:UInt64 = 5
        let deadline = DispatchTime(uptimeNanoseconds:
            now.uptimeNanoseconds + delayInSeconds*UInt64(1e9))
        timer.schedule(deadline: deadline)
        
        if #available(OSX 10.12, *) {
            timer.activate()
        } else {
            XCTFail()
        }
        
        waitForExpectations(timeout: 20, handler: nil)
    }
    
    func testRemoveStaleSharingInvitations() {
        let sharingGroupUUID = UUID().uuidString
        guard case .success = SharingGroupRepository(db).add(sharingGroupUUID: sharingGroupUUID) else {
            XCTFail()
            return
        }
        
        let userId:UserId = 100
        let result = SharingInvitationRepository(db).add(owningUserId: userId, sharingGroupUUID: sharingGroupUUID, permission: .read, allowSocialAcceptance: false, numberAcceptors: 1, expiryDuration: 2)
        
        guard case .success(let uuid) = result else {
            XCTFail()
            return
        }
        
        let exp = expectation(description: "removedStateInvitation")
        
        let timer = DispatchSource.makeTimerSource()
        timer.setEventHandler() {
            let key1 = SharingInvitationRepository.LookupKey.staleExpiryDates
            let removalResult = SharingInvitationRepository(self.db).remove(key: key1)
            
            guard case .removed(numberRows:let number) = removalResult else{
                XCTFail()
                exp.fulfill()
                return
            }
            
            XCTAssert(number == 1)

            let key2 = SharingInvitationRepository.LookupKey.sharingInvitationUUID(uuid: uuid)
            let results = SharingInvitationRepository(self.db).lookup(key: key2, modelInit: SharingInvitation.init)
            
            guard case .noObjectFound = results else {
                XCTFail()
                return
            }
            
            exp.fulfill()
        }
        
        let now = DispatchTime.now()
        let delayInSeconds:UInt64 = 5
        let deadline = DispatchTime(uptimeNanoseconds:
            now.uptimeNanoseconds + delayInSeconds*UInt64(1e9))
        timer.schedule(deadline: deadline)
        
        if #available(OSX 10.12, *) {
            timer.activate()
        } else {
            XCTFail()
        }
        
        waitForExpectations(timeout: 20, handler: nil)
    }
    
    func testDecrementSharingInvitationWithNumberAcceptorsGreaterThan1() {
        let sharingGroupUUID = UUID().uuidString

        guard case .success = SharingGroupRepository(db).add(sharingGroupUUID: sharingGroupUUID) else {
            XCTFail()
            return
        }
        
        let userId:UserId = 100
        let result = SharingInvitationRepository(db).add(owningUserId: userId, sharingGroupUUID: sharingGroupUUID, permission: .read, allowSocialAcceptance: true, numberAcceptors: 2)

        guard case .success(let uuid) = result else {
            XCTFail()
            return
        }
        
        guard SharingInvitationRepository(db).decrementNumberAcceptors(sharingInvitationUUID: uuid) else {
            XCTFail()
            return
        }
        
        let key = SharingInvitationRepository.LookupKey.sharingInvitationUUID(uuid: uuid)
        let results = SharingInvitationRepository(db).lookup(key: key, modelInit: SharingInvitation.init)

        guard case .found(let model) = results,
            let invitation = model as? SharingInvitation else {
            XCTFail()
            return
        }

        XCTAssert(invitation.owningUserId == userId)
        XCTAssert(invitation.permission == .read)
        XCTAssert(invitation.sharingInvitationUUID == uuid)
        XCTAssert(invitation.numberAcceptors == 1)
        XCTAssert(invitation.allowSocialAcceptance == true)
    }
    
    func testDecrementSharingInvitationWithNumberAcceptorsEqualTo1() {
        let sharingGroupUUID = UUID().uuidString

        guard case .success = SharingGroupRepository(db).add(sharingGroupUUID: sharingGroupUUID) else {
            XCTFail()
            return
        }
        
        let userId:UserId = 100
        let result = SharingInvitationRepository(db).add(owningUserId: userId, sharingGroupUUID: sharingGroupUUID, permission: .read, allowSocialAcceptance: true, numberAcceptors: 1)

        guard case .success(let uuid) = result else {
            XCTFail()
            return
        }
        
        guard !SharingInvitationRepository(db).decrementNumberAcceptors(sharingInvitationUUID: uuid) else {
            XCTFail()
            return
        }
        
        let key = SharingInvitationRepository.LookupKey.sharingInvitationUUID(uuid: uuid)
        let results = SharingInvitationRepository(db).lookup(key: key, modelInit: SharingInvitation.init)

        guard case .found(let model) = results,
            let invitation = model as? SharingInvitation else {
            XCTFail()
            return
        }

        XCTAssert(invitation.owningUserId == userId)
        XCTAssert(invitation.permission == .read)
        XCTAssert(invitation.sharingInvitationUUID == uuid)
        XCTAssert(invitation.numberAcceptors == 1)
        XCTAssert(invitation.allowSocialAcceptance == true)
    }
}
