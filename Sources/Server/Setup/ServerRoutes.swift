//
//  ServerRoutes.swift
//  Authentication
//
//  Created by Christopher Prince on 11/26/16.
//
//

import Kitura
import ServerShared

typealias ServerRoute = (ServerEndpoint, (RequestProcessingParameters)->())

// When adding a new controller, you must also add it to the list in Controllers.swift
public class ServerRoutes {
    static func routes() -> [ServerRoute] {
        let utilController = UtilController()
        let userController = UserController()
        let fileController = FileController()
        let sharingAccountsController = SharingAccountsController()
        let sharingGroupsController = SharingGroupsController()
        let pushNotificationsController = PushNotificationsController()

        var result = [
            (ServerEndpoints.healthCheck, utilController.healthCheck),

            (ServerEndpoints.addUser, userController.addUser),
            (ServerEndpoints.checkCreds, userController.checkCreds),
            (ServerEndpoints.removeUser, userController.removeUser),
            
            (ServerEndpoints.index, fileController.index),
            (ServerEndpoints.uploadFile, fileController.uploadFile),
            (ServerEndpoints.downloadFile, fileController.downloadFile),
            (ServerEndpoints.downloadAppMetaData, fileController.downloadAppMetaData),
            (ServerEndpoints.uploadDeletion, fileController.uploadDeletion),
            (ServerEndpoints.getUploadsResults, fileController.getUploadsResults),
            
            (ServerEndpoints.createSharingInvitation, sharingAccountsController.createSharingInvitation),
            (ServerEndpoints.getSharingInvitationInfo, sharingAccountsController.getSharingInvitationInfo),
            (ServerEndpoints.redeemSharingInvitation, sharingAccountsController.redeemSharingInvitation),
            
            (ServerEndpoints.createSharingGroup, sharingGroupsController.createSharingGroup),
            (ServerEndpoints.updateSharingGroup, sharingGroupsController.updateSharingGroup),
            (ServerEndpoints.removeSharingGroup, sharingGroupsController.removeSharingGroup),
            (ServerEndpoints.removeUserFromSharingGroup, sharingGroupsController.removeUserFromSharingGroup),
            
            (ServerEndpoints.registerPushNotificationToken, pushNotificationsController.registerPushNotificationToken),
            (ServerEndpoints.sendPushNotifications, pushNotificationsController.sendPushNotifications)
        ]
        
#if DEBUG
        result += [(ServerEndpoints.checkPrimaryCreds, utilController.checkPrimaryCreds)]
#endif
        return result
    }
}
