//
//  Services.swift
//  Server
//
//  Created by Christopher G Prince on 8/15/20.
//

import Foundation
import LoggerAPI

// My version of dependency injection

class Services {
    let pushNotifications:PushNotificationsService
    let accountManager: AccountManager
    let changeResolverManager: ChangeResolverManager
    let uploader: Uploader
    private var _mockStorage: MockStorage!
    var mockStorage: MockStorage {
        if _mockStorage == nil {
            _mockStorage = MockStorage()
        }
        return _mockStorage
    }
    
    init?(accountManager: AccountManager, changeResolverManager: ChangeResolverManager, uploader: Uploader) {

        var fakePushNotifications = false
#if DEBUG
#if FAKE_PUSH_NOTIFICATIONS
        fakePushNotifications = true
#endif
        if Configuration.server.awssns == nil {

            fakePushNotifications = true
        }
#endif

        if fakePushNotifications {
            guard let pns = FakePushNotifications() else {
                Log.error("Failed during startup: Failed setting up FakePushNotifications")
                return nil
            }
            pushNotifications = pns
        }
        else {
            guard let pns = PushNotifications() else {
                Log.error("Failed during startup: Failed setting up PushNotifications")
                return nil
            }
            pushNotifications = pns
        }

        self.accountManager = accountManager
        self.changeResolverManager = changeResolverManager
        self.uploader = uploader
    }
}
