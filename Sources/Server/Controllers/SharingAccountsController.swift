//
//  SharingAccountsController
//  Server
//
//  Created by Christopher Prince on 4/9/17.
//
//

import Credentials
import SyncServerShared
import LoggerAPI

class SharingAccountsController : ControllerProtocol {
    class func setup() -> Bool {
        return true
    }
    
    init() {
    }
    
    func createSharingInvitation(params:RequestProcessingParameters) {
        assert(params.ep.authenticationLevel == .secondary)
        assert(params.ep.minPermission == .admin)

        guard let createSharingInvitationRequest = params.request as? CreateSharingInvitationRequest else {
            let message = "Did not receive CreateSharingInvitationRequest"
            Log.error(message)
            params.completion(.failure(.message(message)))
            return
        }
        
        guard sharingGroupSecurityCheck(sharingGroupId: createSharingInvitationRequest.sharingGroupId, params: params) else {
            let message = "Failed in sharing group security check."
            Log.error(message)
            params.completion(.failure(.message(message)))
            return
        }
        
        guard let currentSignedInUser = params.currentSignedInUser else {
            let message = "No currentSignedInUser"
            Log.error(message)
            params.completion(.failure(.message(message)))
            return
        }
        
        // 6/20/18; The current user can be a sharing or owning user, and whether or not these users can invite others depends on the permissions they have. See https://github.com/crspybits/SyncServerII/issues/76 And permissions have already been checked before this point in request handling.

        guard let effectiveOwningUserId = currentSignedInUser.effectiveOwningUserId else {
            let message = "Could not get effectiveOwningUserId for inviting user."
            Log.error(message)
            params.completion(.failure(.message(message)))
            return
        }
        
        let result = params.repos.sharing.add(
            owningUserId: effectiveOwningUserId, sharingGroupId: createSharingInvitationRequest.sharingGroupId,
            permission: createSharingInvitationRequest.permission)
        
        guard case .success(let sharingInvitationUUID) = result else {
            let message = "Failed to add Sharing Invitation"
            Log.error(message)
            params.completion(.failure(.message(message)))
            return
        }
        
        let response = CreateSharingInvitationResponse()!
        response.sharingInvitationUUID = sharingInvitationUUID
        params.completion(.success(response))
    }
    
    func redeemSharingInvitation(params:RequestProcessingParameters) {
        assert(params.ep.authenticationLevel == .primary)

        guard let request = params.request as? RedeemSharingInvitationRequest else {
            let message = "Did not receive RedeemSharingInvitationRequest"
            Log.error(message)
            params.completion(.failure(.message(message)))
            return
        }
        
        let userExists = UserController.userExists(userProfile: params.userProfile!, userRepository: params.repos.user)
        switch userExists {
        case .doesNotExist:
            break
        case .error, .exists(_):
            let message = "Could not add user: Already exists!"
            Log.error(message)
            params.completion(.failure(.message(message)))
            return
        }
        
        // Remove stale invitations.
        let removalKey = SharingInvitationRepository.LookupKey.staleExpiryDates
        let removalResult = SharingInvitationRepository(params.db).remove(key: removalKey)
        
        guard case .removed(_) = removalResult else {
            let message = "Failed removing stale sharing invitations"
            Log.error(message)
            params.completion(.failure(.message(message)))
            return
        }

        // What I want to do at this point is to simultaneously and atomically, (a) lookup the sharing invitation, and (b) delete it. I believe that since (i) I'm using mySQL transactions, and (ii) InnoDb with a default transaction level of REPEATABLE READ, this should work by first doing the lookup, and then doing the delete.
        
        let sharingInvitationKey = SharingInvitationRepository.LookupKey.sharingInvitationUUID(uuid: request.sharingInvitationUUID)
        let lookupResult = SharingInvitationRepository(params.db).lookup(key: sharingInvitationKey, modelInit: SharingInvitation.init)
        
        guard case .found(let model) = lookupResult,
            let sharingInvitation = model as? SharingInvitation else {
            let message = "Could not find sharing invitation: \(request.sharingInvitationUUID). Was it stale?"
            Log.error(message)
            params.completion(.failure(.message(message)))
            return
        }
        
        let removalResult2 = SharingInvitationRepository(params.db).remove(key: sharingInvitationKey)
        guard case .removed(let numberRemoved) = removalResult2, numberRemoved == 1 else {
            let message = "Failed removing sharing invitation!"
            Log.error(message)
            params.completion(.failure(.message(message)))
            return
        }
        
        // All seems good. Let's create the new user.
        
        // No database creds because this is a new user-- so use params.profileCreds
        
        let user = User()
        user.username = params.userProfile!.displayName
        user.accountType = AccountType.for(userProfile: params.userProfile!)
        user.credsId = params.userProfile!.id
        user.creds = params.profileCreds!.toJSON(userType:user.accountType.userType)
        user.permission = sharingInvitation.permission
        
        var createInitialOwningUserFile = false
        
        switch user.accountType.userType {
        case .sharing:
            user.owningUserId = sharingInvitation.owningUserId
        case .owning:
            // When the user is an owning user, they will rely on their own cloud storage to upload new files-- if they have upload permissions.
            // Cloud storage folder must be present when redeeming an invitation: a) using an owning account, where b) that owning account type needs a cloud storage folder (e.g., Google Drive), and c) with permissions of >= write.
            if params.profileCreds!.owningAccountsNeedCloudFolderName && sharingInvitation.permission.hasMinimumPermission(.write) {
                guard let cloudFolderName = request.cloudFolderName else {
                    let message = "No cloud folder name given when redeeming sharing invitation using owning account that needs one!"
                    Log.error(message)
                    params.completion(.failure(.message(message)))
                    return
                }
                
                createInitialOwningUserFile = true
                user.cloudFolderName = cloudFolderName
            }
        }
        
        guard let userId = params.repos.user.add(user: user) else {
            let message = "Failed on adding sharing user to User!"
            Log.error(message)
            params.completion(.failure(.message(message)))
            return
        }
        
        guard case .success = params.repos.sharingGroupUser.add(sharingGroupId: sharingInvitation.sharingGroupId, userId: userId) else {
            let message = "Failed on adding sharing group user for new sharing user."
            Log.error(message)
            params.completion(.failure(.message(message)))
            return
        }

        let response = RedeemSharingInvitationResponse()!
        response.sharingGroupId = sharingInvitation.sharingGroupId
        response.userId = userId
        
        // 11/5/17; Up until now I had been calling `generateTokensIfNeeded` for Facebook creds and that had been generating tokens. Somehow, in running my tests today, I'm getting failures from the Facebook API when I try to do this. This may only occur in testing because I'm passing long-lived access tokens. Plus, it's possible this error has gone undiagnosed until now. In testing, there is no need to generate the long-lived access tokens.

        var profileCreds = params.profileCreds!
        profileCreds.accountCreationUser = .userId(userId, user.accountType.userType)
        
        profileCreds.generateTokensIfNeeded(userType: user.accountType.userType, dbCreds: nil, routerResponse: params.routerResponse, success: {
            if createInitialOwningUserFile {                
                // We're creating an account for an owning user. `profileCreds` will be an owning user account and this will implement the CloudStorage protocol.
                guard let cloudStorageCreds = profileCreds as? CloudStorage else {
                    let message = "Could not obtain CloudStorage Creds"
                    Log.error(message)
                    params.completion(.failure(.message(message)))
                    return
                }
        
                UserController.createInitialFileForOwningUser(cloudFolderName: user.cloudFolderName, cloudStorage: cloudStorageCreds) { success in
                    if success {
                        params.completion(.success(response))
                    }
                    else {
                        params.completion(.failure(nil))
                    }
                }
            }
            else {
                params.completion(.success(response))
            }
        }, failure: {
            params.completion(.failure(nil))
        })
    }
}
