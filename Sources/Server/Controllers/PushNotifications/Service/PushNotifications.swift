//
//  PushNotifications.swift
//  Server
//
//  Created by Christopher G Prince on 2/6/19.
//

import Foundation
import ServerShared
import SwiftyAWSSNS
import LoggerAPI

class PushNotifications: PushNotificationsService {
    private let sns:SwiftyAWSSNS
    
    required init?() {
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
    
    func createPlatformEndpoint(apnsToken: String, completion: @escaping (Result<String, Error>) -> ()) {
        sns.createPlatformEndpoint(apnsToken: apnsToken) { result in
            switch result {
            case .error(let error):
                completion(.failure(error))
            case .success(let endpointArn):
                completion(.success(endpointArn))
            }
        }
    }

    func createTopic(topicName: String, completion:@escaping (Result<String, Swift.Error>)->()) {
        sns.createTopic(topicName: topicName) { result in
            switch result {
            case .error(let error):
                completion(.failure(error))
            case .success(let topicArn):
                completion(.success(topicArn))
            }
        }
    }
    
    func subscribe(endpointArn: String, topicArn: String, completion:@escaping (Result<String, Swift.Error>)->()) {
        sns.subscribe(endpointArn: endpointArn, topicArn: topicArn) { result in
            switch result {
            case .error(let error):
                completion(.failure(error))
            case .success(let subscriptionARN):
                completion(.success(subscriptionARN))
            }
        }
    }
    
    func publish(message: String, target: SwiftyAWSSNS.PublishTarget, jsonMessageStructure: Bool = true, completion:@escaping (Result<String, Swift.Error>)->()) {
        sns.publish(message: message, target: target, jsonMessageStructure: jsonMessageStructure) { result in
            switch result {
            case .error(let error):
                completion(.failure(error))
            case .success(let messageId):
                completion(.success(messageId))
            }
        }
    }
}
