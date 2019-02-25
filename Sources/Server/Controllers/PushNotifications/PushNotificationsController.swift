//
//  PushNotificationsController.swift
//  Server
//
//  Created by Christopher G Prince on 2/6/19.
//

import LoggerAPI
import SyncServerShared
import Foundation
import SwiftyAWSSNS

class PushNotificationsController : ControllerProtocol {
    class func setup() -> Bool {
        return true
    }
    
    func registerPushNotificationToken(params:RequestProcessingParameters) {
        guard let request = params.request as? RegisterPushNotificationTokenRequest else {
            let message = "Did not receive RegisterPushNotificationTokenRequest"
            Log.error(message)
            params.completion(.failure(.message(message)))
            return
        }

        guard let pn = PushNotifications() else {
            params.completion(.failure(nil))
            return
        }
        
        let userId = params.currentSignedInUser!.userId!
        let topicName = PushNotifications.topicName(userId: userId)

        pn.sns.createPlatformEndpoint(apnsToken: request.pushNotificationToken) { response in
            switch response {
            case .success(let endpointArn):
                pn.sns.createTopic(topicName: topicName) { response in
                    switch response {
                    case .success(let topicArn):
                        pn.sns.subscribe(endpointArn: endpointArn, topicArn: topicArn) { response in
                            switch response {
                            case .success:
                                guard params.repos.user.updatePushNotificationTopic(
                                    forUserId: userId, topic: topicArn) else {
                                    let message = "Failed updating user topic."
                                    Log.error(message)
                                    params.completion(.failure(.message(message)))
                                    return
                                }
                                
                                let response = RegisterPushNotificationTokenResponse()
                                params.completion(.success(response))
                                return
                            case .error(let error):
                                let message = "Failed on subscribe: \(error)"
                                Log.error(message)
                                params.completion(.failure(.message(message)))
                                return
                            }
                        }
                    case .error(let error):
                        let message = "Failed on createTopic: \(error)"
                        Log.error(message)
                        params.completion(.failure(.message(message)))
                        return
                    }
                }
            case .error(let error):
                let message = "Failed on createPlatformEndpoint: \(error)"
                Log.error(message)
                params.completion(.failure(.message(message)))
                return
            }
        }
    }
}
