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
        guard let accessKeyId = Constants.session.awssns.accessKeyId,
            let secretKey = Constants.session.awssns.secretKey,
            let region = Constants.session.awssns.region,
            let platformApplicationArn = Constants.session.awssns.platformApplicationArn else {
            let message = "Missing one of the Constants.session.awssns values!"
            Log.error(message)
            return nil
        }
        
        sns = SwiftyAWSSNS(accessKeyId: accessKeyId, secretKey: secretKey, region: region, platformApplicationArn: platformApplicationArn)
    }
    
    static func topicName(userId: UserId) -> String {
        return "\(userId)"
    }
    
    // The users in the given array will all have PN topics.
    func send(message: String, toUsers users: [User], completion: @escaping (Bool)->()) {
        // Base case.
        if users.count == 0 {
            completion(true)
            return
        }
        
        let user = users[0]
        let topic = user.pushNotificationTopic!
        
        sns.publish(message: message, target: .topicArn(topic)) { [unowned self] response in
            switch response {
            case .success:
                DispatchQueue.main.async {
                    let tail = (users.count > 0) ?
                        Array(users[1..<users.count]) : []
                    self.send(message: message, toUsers: tail, completion: completion)
                }
            case .error(let error):
                Log.error("\(error)")
                completion(false)
            }
        }
    }
}
