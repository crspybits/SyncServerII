//
//  SpecificDatabaseTests_SharingInvitationRepository.swift
//  Server
//
//  Created by Christopher Prince on 4/10/17.
//
//

import XCTest
@testable import Server
import PerfectLib
import Foundation
import Dispatch
import SyncServerShared

class SpecificDatabaseTests_SharingInvitationRepository: ServerTestCase, LinuxTestable {

    override func setUp() {
        super.setUp()
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }
    
    override func tearDown() {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
        super.tearDown()
    }

    func testAddingSharingInvitation() {
        let userId:UserId = 100
        let result = SharingInvitationRepository(db).add(owningUserId: userId, sharingPermission: .read)
        
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
        XCTAssert(invitation.sharingPermission == .read)
        XCTAssert(invitation.sharingInvitationUUID == uuid)
    }
    
    func testAttemptToRemoveStaleInvitationsThatAreNotStale() {
        let userId:UserId = 100
        let result = SharingInvitationRepository(db).add(owningUserId: userId, sharingPermission: .write)
        
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
            XCTAssert(invitation.sharingPermission == .write)
            XCTAssert(invitation.sharingInvitationUUID == uuid)
            
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
        let userId:UserId = 100
        let result = SharingInvitationRepository(db).add(owningUserId: userId, sharingPermission: .read, expiryDuration: 2)
        
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
}

extension SpecificDatabaseTests_SharingInvitationRepository {
    static var allTests : [(String, (SpecificDatabaseTests_SharingInvitationRepository) -> () throws -> Void)] {
        return [
            ("testAddingSharingInvitation", testAddingSharingInvitation),
            ("testAttemptToRemoveStaleInvitationsThatAreNotStale", testAttemptToRemoveStaleInvitationsThatAreNotStale),
            ("testRemoveStaleSharingInvitations", testRemoveStaleSharingInvitations)
        ]
    }
    
    func testLinuxTestSuiteIncludesAllTests() {
        linuxTestSuiteIncludesAllTests(testType: SpecificDatabaseTests_SharingInvitationRepository.self)
    }
}
