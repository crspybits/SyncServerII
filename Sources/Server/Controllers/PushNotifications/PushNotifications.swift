//
//  PushNotifications.swift
//  Server
//
//  Created by Christopher G Prince on 2/6/19.
//

import Foundation
import SyncServerShared
import SwiftyAWSSNS
import LoggerAPI

class PushNotifications {
    private(set) var sns:SwiftyAWSSNS!
    
    init?() {
        guard let accessKeyId = Configuration.server.awssns?.accessKeyId,
            let secretKey = Configuration.server.awssns?.secretKey,
            let region = Configuration.server.awssns?.region,
            let platformApplicationArn = Configuration.server.awssns?.platformApplicationArn else {
            let message = "Missing one of the Configuration.server.awssns values!"
            Log.error(message)
            return nil
        }
        
        Log.debug("accessKeyId: \(accessKeyId)")
        Log.debug(("secretKey: \(secretKey)"))
        Log.debug("region: \(region)")
        Log.debug("platformApplicationArn: \(platformApplicationArn)")
        
        sns = SwiftyAWSSNS(accessKeyId: accessKeyId, secretKey: secretKey, region: region, platformApplicationArn: platformApplicationArn)
    }
    
    static func topicName(userId: UserId) -> String {
        return "\(userId)"
    }
    
    static func format(message: String) -> String? {
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
    func send(formattedMessage message: String, toUsers users: [User], completion: @escaping (_ success: Bool)->()) {
        let async = AsyncTailRecursion()
        async.start {
            self.sendAux(formattedMessage: message, toUsers: users, async: async, completion: completion)
        }
    }
    
    func sendAux(formattedMessage message: String, toUsers users: [User], async: AsyncTailRecursion, completion: @escaping (_ success: Bool)->()) {
        // Base case.
        if users.count == 0 {
            completion(true)
            async.done()
            return
        }
        
        let user = users[0]
        let topic = user.pushNotificationTopic!
        
        Log.debug("Sending push notification: \(message) to devices subscribed to topic \(topic) for user \(user.username!)")
        
        sns.publish(message: message, target: .topicArn(topic)) { [unowned self] response in
            switch response {
            case .success:
                async.next {
                    let tail = (users.count > 0) ?
                        Array(users[1..<users.count]) : []
                    self.sendAux(formattedMessage: message, toUsers: tail, async: async, completion: completion)
                }
            case .error(let error):
                Log.error("Failed on SNS publish: \(error); sending message: \(message)")
                completion(false)
                async.done()
            }
        }
    }
}
