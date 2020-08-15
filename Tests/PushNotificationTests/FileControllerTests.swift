
import XCTest
@testable import Server
@testable import TestsCommon
import LoggerAPI
import Foundation
import ServerShared
import ServerAccount

// Run this only with the runTests script and the suite: It uses the fake push notifications service.

class SendPushNotificationsTests: ServerTestCase {
    override func setUp() {
        super.setUp()
    }
    
    override func tearDown() {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
        super.tearDown()
    }

    func runSendPushNotifications(withSharingUUID: Bool) {
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
        request.pushNotificationToken = fakeToken

        let result = registerPushNotificationToken(request: request, deviceUUID: deviceUUID)
        XCTAssert(result != nil)
        guard case .found(let model2) = UserRepository(db).lookup(key: key, modelInit: User.init), let userObject2 = model2 as? User else {
            XCTFail()
            return
        }
        
        guard userObject2.pushNotificationTopic != nil else {
            XCTFail()
            return
        }
        
        let sendRequest = SendPushNotificationsRequest()
        sendRequest.message = "Hello, world!"
        
        if withSharingUUID {
            sendRequest.sharingGroupUUID = sharingGroupUUID
        }
        
        let sendResponse = sendPushNotification(request: sendRequest, deviceUUID: deviceUUID)
        if withSharingUUID {
            XCTAssert(sendResponse != nil)
        }
        else {
            XCTAssert(sendResponse == nil)
        }
    }
    
    func testSendPushNotificationsWithNoSharingUUIDFails() throws {
        runSendPushNotifications(withSharingUUID: false)
    }
    
    func testSendPushNotificationsWithSharingUUIDWorks() throws {
        runSendPushNotifications(withSharingUUID: true)
    }
    
    func runSendPushNotifications(withMessage: Bool) {
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
        request.pushNotificationToken = fakeToken

        let result = registerPushNotificationToken(request: request, deviceUUID: deviceUUID)
        XCTAssert(result != nil)
        guard case .found(let model2) = UserRepository(db).lookup(key: key, modelInit: User.init), let userObject2 = model2 as? User else {
            XCTFail()
            return
        }
        
        guard userObject2.pushNotificationTopic != nil else {
            XCTFail()
            return
        }
        
        let sendRequest = SendPushNotificationsRequest()
            sendRequest.sharingGroupUUID = sharingGroupUUID

        if withMessage {
            sendRequest.message = "Hello, world!"
        }
        
        let sendResponse = sendPushNotification(request: sendRequest, deviceUUID: deviceUUID)
        if withMessage {
            XCTAssert(sendResponse != nil)
        }
        else {
            XCTAssert(sendResponse == nil)
        }
    }
    
    func testSendPushNotificationsWithNoMessageFails() {
        runSendPushNotifications(withMessage: false)
    }

    func testSendPushNotificationsWithMessageWorks() {
        runSendPushNotifications(withMessage: true)
    }
    
    func testSendPushNotificationsWithTwoUsersInSharingGroupWorks() {
        let sharingGroupUUID1 = Foundation.UUID().uuidString
        let sharingGroupUUID2 = Foundation.UUID().uuidString
        let deviceUUID1 = Foundation.UUID().uuidString
        let deviceUUID2 = Foundation.UUID().uuidString
        let fakeToken1 = Foundation.UUID().uuidString
        let fakeToken2 = Foundation.UUID().uuidString

        guard let addUserResponse1 = self.addNewUser(testAccount: .google1, sharingGroupUUID: sharingGroupUUID1, deviceUUID:deviceUUID1, cloudFolderName: ServerTestCase.cloudFolderName) else {
            XCTFail()
            return
        }
        
        guard let addUserResponse2 = self.addNewUser(testAccount: .dropbox1, sharingGroupUUID: sharingGroupUUID2, deviceUUID:deviceUUID2, cloudFolderName: ServerTestCase.cloudFolderName) else {
            XCTFail()
            return
        }
        
        let permission = Permission.read
        let invitationUUID: String! = createSharingInvitation(testAccount: .google1, permission: permission, numberAcceptors: 1, allowSharingAcceptance: false, deviceUUID: deviceUUID1, sharingGroupUUID: sharingGroupUUID1)
        
        guard invitationUUID != nil else {
            XCTFail()
            return
        }

        guard let redeemResult = redeemSharingInvitation(sharingUser: .dropbox1, deviceUUID: deviceUUID2, canGiveCloudFolderName: false, sharingInvitationUUID: invitationUUID) else {
            XCTFail()
            return
        }

        let request1 = RegisterPushNotificationTokenRequest()
        request1.pushNotificationToken = fakeToken1

        let registerResult1 = registerPushNotificationToken(request: request1, testAccount: .google1, deviceUUID: deviceUUID1)
        guard registerResult1 != nil else {
            XCTFail()
            return
        }
        
        let request2 = RegisterPushNotificationTokenRequest()
        request2.pushNotificationToken = fakeToken2

        let registerResult2 = registerPushNotificationToken(request: request2, testAccount: .dropbox1, deviceUUID: deviceUUID2)
        guard registerResult2 != nil else {
            XCTFail()
            return
        }

        let sendRequest = SendPushNotificationsRequest()
        sendRequest.sharingGroupUUID = sharingGroupUUID1
        sendRequest.message = "Hello, world!"
        
        let sendResponse = sendPushNotification(request: sendRequest, deviceUUID: deviceUUID1)
        XCTAssert(sendResponse != nil)
    }
}


