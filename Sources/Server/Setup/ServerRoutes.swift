//
//  ServerRoutes.swift
//  Authentication
//
//  Created by Christopher Prince on 11/26/16.
//
//

import Kitura
import ServerShared

// When adding a new controller, you must also add it to the list in Controllers.swift
public class ServerRoutes {
    class func add(proxyRouter:CreateRoutes) {
        let utilController = UtilController()
        proxyRouter.addRoute(ep: ServerEndpoints.healthCheck, processRequest: utilController.healthCheck)
#if DEBUG
        proxyRouter.addRoute(ep: ServerEndpoints.checkPrimaryCreds, processRequest: utilController.checkPrimaryCreds)
#endif

        let userController = UserController()
        proxyRouter.addRoute(ep: ServerEndpoints.addUser, processRequest: userController.addUser)
        proxyRouter.addRoute(ep: ServerEndpoints.checkCreds, processRequest: userController.checkCreds)
        proxyRouter.addRoute(ep: ServerEndpoints.removeUser, processRequest: userController.removeUser)
        
        let fileController = FileController()
        proxyRouter.addRoute(ep: ServerEndpoints.index, processRequest: fileController.index)
        proxyRouter.addRoute(ep: ServerEndpoints.uploadFile, processRequest: fileController.uploadFile)
        proxyRouter.addRoute(ep: ServerEndpoints.downloadFile, processRequest: fileController.downloadFile)
        proxyRouter.addRoute(ep: ServerEndpoints.downloadAppMetaData, processRequest: fileController.downloadAppMetaData)
        proxyRouter.addRoute(ep: ServerEndpoints.getUploads, processRequest: fileController.getUploads)
        proxyRouter.addRoute(ep: ServerEndpoints.uploadDeletion, processRequest: fileController.uploadDeletion)
        proxyRouter.addRoute(ep: ServerEndpoints.getUploadsResults, processRequest: fileController.getUploadsResults)
        
        let sharingAccountsController = SharingAccountsController()
        proxyRouter.addRoute(ep: ServerEndpoints.createSharingInvitation, processRequest: sharingAccountsController.createSharingInvitation)
        proxyRouter.addRoute(ep: ServerEndpoints.getSharingInvitationInfo, processRequest: sharingAccountsController.getSharingInvitationInfo)
        proxyRouter.addRoute(ep: ServerEndpoints.redeemSharingInvitation, processRequest: sharingAccountsController.redeemSharingInvitation)
        
        let sharingGroupsController = SharingGroupsController()
        proxyRouter.addRoute(ep: ServerEndpoints.createSharingGroup, processRequest: sharingGroupsController.createSharingGroup)
        proxyRouter.addRoute(ep: ServerEndpoints.updateSharingGroup, processRequest: sharingGroupsController.updateSharingGroup)
        proxyRouter.addRoute(ep: ServerEndpoints.removeSharingGroup, processRequest: sharingGroupsController.removeSharingGroup)
        proxyRouter.addRoute(ep: ServerEndpoints.removeUserFromSharingGroup, processRequest: sharingGroupsController.removeUserFromSharingGroup)
        
        let pushNotificationsController = PushNotificationsController()
        proxyRouter.addRoute(ep: ServerEndpoints.registerPushNotificationToken, processRequest: pushNotificationsController.registerPushNotificationToken)
    }
}
