//
//  PushNotificationsService.swift
//  Server
//
//  Created by Christopher G Prince on 8/14/20.
//

import Foundation
import SwiftyAWSSNS
import LoggerAPI
import ServerShared

enum PushNotificationsServiceErrors: Swift.Error {
    case noPushNotificationTopic
}

protocol PushNotificationsService: AnyObject {
    init?()
    
    // On success, completion returns the endpointArn created
    // https://docs.aws.amazon.com/sns/latest/api/API_CreatePlatformEndpoint.html
    func createPlatformEndpoint(apnsToken: String,
        completion:@escaping (Result<String, Swift.Error>)->())

    // On success, responds with Topic ARN.
    // https://docs.aws.amazon.com/sns/latest/api/API_CreateTopic.html
    func createTopic(topicName: String, completion:@escaping (Result<String, Swift.Error>)->())

    // On success, returns a subscription ARN.
    // https://docs.aws.amazon.com/sns/latest/api/API_Subscribe.html
    func subscribe(endpointArn: String, topicArn: String, completion:@escaping (Result<String, Swift.Error>)->())
    
    // https://docs.aws.amazon.com/sns/latest/api/API_Publish.html
    // On success, returns a messageId.
    // See the tests for examples of the message formats.
    func publish(message: String, target: SwiftyAWSSNS.PublishTarget, jsonMessageStructure: Bool, completion:@escaping (Result<String, Swift.Error>)->())
}

extension PushNotificationsService {
    func topicName(userId: UserId) -> String {
        return "\(userId)"
    }
    
    func format(message: String) -> String? {
       // Format of messages: https://developer.apple.com/library/archive/documentation/NetworkingInternet/Conceptual/RemoteNotificationsPG/CreatingtheNotificationPayload.html
        // https://developer.apple.com/library/archive/documentation/NetworkingInternet/Conceptual/RemoteNotificationsPG/PayloadKeyReference.html
        
        func strForJSON(json: Any) -> String? {
            if let result = try? JSONSerialization.data(withJSONObject: json, options: JSONSerialization.WritingOptions(rawValue: 0)) {
                return String(data: result, encoding: .utf8)
            }
            
            Log.error("Failed in strForJSON: \(json)")
            return nil
        }
        
        let messageContentsDict = ["aps":
            ["alert": message,
            "sound": "default"]
        ]
        
        guard let messageContentsString = strForJSON(json: messageContentsDict) else {
            Log.error("Failed converting messageContentsString: \(messageContentsDict)")
            return nil
        }
        
        // Looks like the top level key must be "APNS" for production; see https://forums.aws.amazon.com/thread.jspa?threadID=145907
        // 2/9/19; Without the "default" key, I'm getting a failure.
        let messageDict = ["APNS_SANDBOX": messageContentsString,
            "APNS": messageContentsString,
            "default": messageContentsString
        ]

        guard let messageString = strForJSON(json: messageDict) else {
            Log.error("Failed converting messageString: \(messageDict)")
            return nil
        }
        
        return messageString
    }
    
    // The users in the given array will all have PN topics.
    // Use the format method above to format the message before passing to this method.
    // Returns true iff success
    func send(formattedMessage message: String, toUsers users: [User]) -> Bool {
        func apply(user: User, completion: @escaping (Swift.Result<Void, Error>) -> ()) {
            guard let topic = user.pushNotificationTopic else {
                completion(.failure(PushNotificationsServiceErrors.noPushNotificationTopic))
                return
            }
            
            Log.debug("Sending push notification: \(message) to devices subscribed to topic \(topic) for user \(String(describing: user.username))")
            
            publish(message: message, target: .topicArn(topic), jsonMessageStructure: true) { response in
                switch response {
                case .success:
                    completion(.success(()))
                case .failure(let error):
                    Log.error("Failed on SNS publish: \(error); sending message: \(message)")
                    completion(.failure(error))
                }
            }
        }
        
        let (_, errors) = users.synchronouslyRun(apply: apply)
        return errors.count == 0
    }
}
