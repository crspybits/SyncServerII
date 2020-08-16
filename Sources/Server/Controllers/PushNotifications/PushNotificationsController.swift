//
//  PushNotificationsController.swift
//  Server
//
//  Created by Christopher G Prince on 2/6/19.
//

import LoggerAPI
import ServerShared
import Foundation
import SwiftyAWSSNS
import ServerAccount

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
        
        guard let userId = params.currentSignedInUser?.userId else {
            let message = "Could not get userId"
            Log.error(message)
            params.completion(.failure(.message(message)))
            return
        }
        
        let topicName = params.services.pushNotifications.topicName(userId: userId)

        params.services.pushNotifications.createPlatformEndpoint(apnsToken: request.pushNotificationToken) { response in
            switch response {
            case .success(let endpointArn):
                params.services.pushNotifications.createTopic(topicName: topicName) { response in
                    switch response {
                    case .success(let topicArn):
                        params.services.pushNotifications.subscribe(endpointArn: endpointArn, topicArn: topicArn) { response in
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
                                
                            case .failure(let error):
                                let message = "Failed on subscribe: \(error)"
                                Log.error(message)
                                params.completion(.failure(.message(message)))
                                return
                            }
                        }
                    case .failure(let error):
                        let message = "Failed on createTopic: \(error)"
                        Log.error(message)
                        params.completion(.failure(.message(message)))
                        return
                    }
                }
            case .failure(let error):
                let message = "Failed on createPlatformEndpoint: \(error)"
                Log.error(message)
                params.completion(.failure(.message(message)))
                return
            }
        }
    }
}
