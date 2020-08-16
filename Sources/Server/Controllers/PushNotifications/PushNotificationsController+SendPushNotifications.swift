//
//  PushNotificationsController+SendPushNotifications.swift
//  Server
//
//  Created by Christopher G Prince on 8/14/20.
//

import ServerShared
import LoggerAPI

extension PushNotificationsController {
    func sendPushNotifications(params:RequestProcessingParameters) {
        guard let request = params.request as? SendPushNotificationsRequest else {
            let message = "Did not receive SendPushNotificationsRequest"
            Log.error(message)
            params.completion(.failure(.message(message)))
            return
        }
        
        guard let sharingGroupUUID = request.sharingGroupUUID else {
            let message = "No sharingGroupUUID"
            Log.error(message)
            params.completion(.failure(.message(message)))
            return
        }
        
        guard let message = request.message else {
            let message = "No message."
            Log.error(message)
            params.completion(.failure(.message(message)))
            return
        }
        
        guard sharingGroupSecurityCheck(sharingGroupUUID: sharingGroupUUID, params: params) else {
            let message = "Failed in sharing group security check."
            Log.error(message)
            params.completion(.failure(.message(message)))
            return
        }
        
        guard let currentSignedInUser = params.currentSignedInUser else {
            let message = "Could not get currentSignedInUser"
            Log.error(message)
            params.completion(.failure(.message(message)))
            return
        }
        
        let success = sendNotifications(fromUser: currentSignedInUser, forSharingGroupUUID: sharingGroupUUID, message: message, params: params)
        if success {
            let response = SendPushNotificationsResponse()
            params.completion(.success(response))
        }
        else {
            let message = "Failed on sendNotifications in finishDoneUploads"
            Log.error(message)
            params.completion(.failure(.message(message)))
        }
    }
    
    // Returns true iff success.
    private func sendNotifications(fromUser: User, forSharingGroupUUID sharingGroupUUID: String, message: String, params:RequestProcessingParameters) -> Bool {

        guard var users:[User] = params.repos.sharingGroupUser.sharingGroupUsers(forSharingGroupUUID: sharingGroupUUID) else {
            Log.error(("sendNotifications: Failed to get sharing group users!"))
            return false
        }
        
        // Remove sending user from users. They already know they uploaded/deleted-- no point in sending them a notification.
        // Also remove any users that don't have topics-- i.e., they don't have any devices registered for push notifications.
        users = users.filter { user in
            user.userId != fromUser.userId && user.pushNotificationTopic != nil
        }
        
        let key = SharingGroupRepository.LookupKey.sharingGroupUUID(sharingGroupUUID)
        let sharingGroupResult = params.repos.sharingGroup.lookup(key: key, modelInit: SharingGroup.init)
        var sharingGroup: SharingGroup!
        
        switch sharingGroupResult {
        case .found(let model):
            sharingGroup = model as? SharingGroup
            guard sharingGroup != nil else {
                Log.error("sendNotifications: Failed converting to SharingGroup")
                return false
            }
            
        case .error(let error):
            Log.error("sendNotifications: \(error)")
            return false
            
        case .noObjectFound:
            Log.error("sendNotifications: No object found!")
            return false
        }
        
        guard let username = fromUser.username else {
            Log.error("sendNotifications: No username!")
            return false
        }
        
        var modifiedMessage = "\(username)"
        
        if let name = sharingGroup.sharingGroupName {
            modifiedMessage += ", \(name)"
        }
        
        modifiedMessage += ": " + message
        
        guard let formattedMessage = params.services.pushNotifications.format(message: modifiedMessage) else {
            Log.error("sendNotifications: Failed on formatting message.")
            return false
        }
        
        guard params.services.pushNotifications.send(formattedMessage: formattedMessage, toUsers: users) else {
            return false
        }
        
        return true
    }
}
