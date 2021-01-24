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
    lazy var mockStorage = MockStorage()
    let uploaderServices: UploaderServices
    var periodicUploader:PeriodicUploader?
    
    init?(accountManager: AccountManager, changeResolverManager: ChangeResolverManager) {

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
        
        uploaderServices = UploaderHelpers(accountManager: accountManager, changeResolverManager: changeResolverManager)
        
        if let periodic = Configuration.server.periodicUploader, periodic.canRun {
            periodicUploader = PeriodicUploader(interval: periodic.interval, services: uploaderServices)
        }
    }
    
    deinit {
        Log.debug("Services: deinit")
    }
}

extension Services: PeriodicUploaderDelegate {
    func resetPeriodicUploader(_ uploader: Uploader) {
        periodicUploader?.reset()
    }
}
