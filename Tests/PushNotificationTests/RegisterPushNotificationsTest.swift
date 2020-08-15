//
//  RegisterPushNotificationsTest.swift
//  Server
//
//  Created by Christopher G Prince on 8/14/20.
//

import XCTest
@testable import Server
@testable import TestsCommon
import LoggerAPI
import Foundation
import ServerShared
import ServerAccount

// Run this only with the runTests script and the suite: It uses the fake push notifications service.

class RegisterPushNotificationsTest: ServerTestCase {
    func runRegisterPushNotification(withToken: Bool) {
        let sharingGroupUUID = Foundation.UUID().uuidString
        let deviceUUID = Foundation.UUID().uuidString
        let fakeToken = Foundation.UUID().uuidString
        
        guard let addUserResponse = self.addNewUser(sharingGroupUUID: sharingGroupUUID, deviceUUID:deviceUUID, cloudFolderName: ServerTestCase.cloudFolderName) else {
            XCTFail()
            return
        }
        
        guard let userId = addUserResponse.userId else {
            XCTFail()
            return
        }
        
        let key = UserRepository.LookupKey.userId(userId)
        guard case .found(let model1) = UserRepository(db).lookup(key: key, modelInit: User.init), let userObject1 = model1 as? User else {
            XCTFail()
            return
        }
        
        XCTAssert(userObject1.pushNotificationTopic == nil)

        let request = RegisterPushNotificationTokenRequest()
        if withToken {
            request.pushNotificationToken = fakeToken
        }

        let result = registerPushNotificationToken(request: request, deviceUUID: deviceUUID)
        if withToken {
            XCTAssert(result != nil)
            guard case .found(let model2) = UserRepository(db).lookup(key: key, modelInit: User.init), let userObject2 = model2 as? User else {
                XCTFail()
                return
            }
            
            XCTAssert(userObject2.pushNotificationTopic != nil)
        }
        else {
            XCTAssert(result == nil)
        }
    }
    
    func testRegisterPushNotificationWithNoTokenFails() throws {
        runRegisterPushNotification(withToken: false)
    }

    func testRegisterPushNotificationWithTokenWorks() throws {
        runRegisterPushNotification(withToken: true)
    }
}
