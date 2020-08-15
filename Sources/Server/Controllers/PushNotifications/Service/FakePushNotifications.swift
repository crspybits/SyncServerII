//
//  FakePushNotifications.swift
//  Server
//
//  Created by Christopher G Prince on 8/14/20.
//

import Foundation
import SwiftyAWSSNS

class FakePushNotifications: PushNotificationsService {
    required init?() {}
    
    // Simple fakes, with some async to simulate network requests.
    
    private func async(run: @escaping ()->()) {
        DispatchQueue.global().asyncAfter(deadline: .now() + .milliseconds(200)) {
            run()
        }
    }
    
    func createPlatformEndpoint(apnsToken: String, completion: @escaping (Result<String, Error>) -> ()) {
        async {
            completion(.success(Foundation.UUID().uuidString))
        }
    }
    
    func createTopic(topicName: String, completion: @escaping (Result<String, Error>) -> ()) {
        async {
            completion(.success(Foundation.UUID().uuidString))
        }
    }
    
    func subscribe(endpointArn: String, topicArn: String, completion: @escaping (Result<String, Error>) -> ()) {
        async {
            completion(.success(Foundation.UUID().uuidString))
        }
    }

    func publish(message: String, target: SwiftyAWSSNS.PublishTarget, jsonMessageStructure: Bool, completion: @escaping (Result<String, Error>) -> ()) {
        async {
            completion(.success(Foundation.UUID().uuidString))
        }
    }
}
