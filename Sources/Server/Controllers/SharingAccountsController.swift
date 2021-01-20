//
//  SharingAccountsController
//  Server
//
//  Created by Christopher Prince on 4/9/17.
//
//

import Credentials
import ServerShared
import LoggerAPI
import KituraNet
import Foundation
import ServerAccount

class SharingAccountsController : ControllerProtocol {
    class func setup() -> Bool {
        return true
    }
    
    init() {
    }
    
    func createSharingInvitation(params:RequestProcessingParameters) {
        assert(params.ep.authenticationLevel == .secondary)
        assert(params.ep.sharing?.minPermission == .admin)

        guard let createSharingInvitationRequest = params.request as? CreateSharingInvitationRequest else {
            let message = "Did not receive CreateSharingInvitationRequest"
            Log.error(message)
            params.completion(.failure(.message(message)))
            return
        }
        
        guard sharingGroupSecurityCheck(sharingGroupUUID: createSharingInvitationRequest.sharingGroupUUID, params: params) else {
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

        guard case .found(let effectiveOwningUserId) = Controllers.getEffectiveOwningUserId(user: currentSignedInUser, sharingGroupUUID: createSharingInvitationRequest.sharingGroupUUID, sharingGroupUserRepo: params.repos.sharingGroupUser) else {
            let message = "Could not get effectiveOwningUserId for inviting user."
            Log.error(message)
            params.completion(.failure(.message(message)))
            return
        }
        
        let allowSocialAcceptance = createSharingInvitationRequest.allowSocialAcceptance
        let numberAcceptors = createSharingInvitationRequest.numberOfAcceptors
        
        guard numberAcceptors >= 1 && numberAcceptors <= ServerConstants.maxNumberSharingInvitationAcceptors else {
            let message = "numberAcceptors <= 0 or > \(ServerConstants.maxNumberSharingInvitationAcceptors)"
            Log.error(message)
            params.completion(.failure(.message(message)))
            return
        }
        
        let expiry = createSharingInvitationRequest.expiryDuration
        if let expiry = expiry, expiry <= 0 {
            let message = "Expiry duration(\(expiry)) <= 0"
            Log.error(message)
            params.completion(.failure(.message(message)))
            return
        }
        
        let result = params.repos.sharing.add(
            owningUserId: effectiveOwningUserId, sharingGroupUUID: createSharingInvitationRequest.sharingGroupUUID,
            permission: createSharingInvitationRequest.permission, allowSocialAcceptance: allowSocialAcceptance, numberAcceptors: numberAcceptors, expiryDuration: expiry ?? ServerConstants.sharingInvitationExpiryDuration)
        
        guard case .success(let sharingInvitationUUID) = result else {
            let message = "Failed to add Sharing Invitation"
            Log.error(message)
            params.completion(.failure(.message(message)))
            return
        }
        
        let response = CreateSharingInvitationResponse()
        response.sharingInvitationUUID = sharingInvitationUUID
        params.completion(.success(response))
    }
    
    func getSharingInvitationInfo(params:RequestProcessingParameters) {
        assert(params.ep.authenticationLevel == .none)
        
        guard let request = params.request as? GetSharingInvitationInfoRequest else {
            let message = "Did not receive GetSharingInvitationInfoRequest"
            Log.error(message)
            params.completion(.failure(.message(message)))
            return
        }
        
        // I'm not going to fiddle with removing expired invitations here. Just seems wrong with a get info method.
        let sharingInvitationKey = SharingInvitationRepository.LookupKey.unexpiredSharingInvitationUUID(uuid: request.sharingInvitationUUID)
        let lookupResult = SharingInvitationRepository(params.db).lookup(key: sharingInvitationKey, modelInit: SharingInvitation.init)
        
        guard case .found(let model) = lookupResult,
            let sharingInvitation = model as? SharingInvitation else {
                let message = "Could not find sharing invitation: \(String(describing: request.sharingInvitationUUID)). Was it stale?"
            Log.error(message)
            params.completion(.failure(.messageWithStatus(message, HTTPStatusCode.gone)))
            return
        }
        
        let response = GetSharingInvitationInfoResponse()
        response.permission = sharingInvitation.permission
        response.allowSocialAcceptance = sharingInvitation.allowSocialAcceptance
        params.completion(.success(response))
    }
    
    private func redeem(params:RequestProcessingParameters, request: RedeemSharingInvitationRequest, sharingInvitation: SharingInvitation,
                        sharingInvitationKey: SharingInvitationRepository.LookupKey, completion: @escaping ((RequestProcessingParameters.Response)->())) {
        
        guard let accountScheme = params.accountProperties?.accountScheme else {
            let message = "Could not get account scheme from account properties!"
            Log.error(message)
            params.completion(.failure(.message(message)))
            return
        }

        if !sharingInvitation.allowSocialAcceptance {
            guard accountScheme.userType == .owning else {
                let message = "Invitation does not allow social acceptance, but signed in user is not owning"
                Log.error(message)
                params.completion(.failure(.messageWithStatus(message, HTTPStatusCode.forbidden)))
                return
            }
        }

        guard sharingInvitation.numberAcceptors >= 1 else {
            let message = "Number of acceptors was 0 or less."
            Log.error(message)
            params.completion(.failure(.message(message)))
            return
        }

        if sharingInvitation.numberAcceptors == 1 {
            let removalResult2 = params.repos.sharing.retry {
                return params.repos.sharing.remove(key: sharingInvitationKey)
            }
            guard case .removed(let numberRemoved) = removalResult2, numberRemoved == 1 else {
                let message = "Failed removing sharing invitation!"
                Log.error(message)
                completion(.failure(.message(message)))
                return
            }
        }
        else {
            // numberAcceptors should be > 1
            guard params.repos.sharing.decrementNumberAcceptors(sharingInvitationUUID: sharingInvitation.sharingInvitationUUID) else {
                let message = "Could not decrement number acceptors."
                Log.error(message)
                completion(.failure(.message(message)))
                return
            }
        }

        // The user can either: (a) already be on the system -- so this will be a request to add a sharing group to an existing user, or (b) this is a request to both create a user and have them join a sharing group.
        
        guard let credsId = params.userProfile?.id else {
            let message = "Could not get credsId from user profile."
            Log.error(message)
            completion(.failure(.message(message)))
            return
        }
        
        let userExists = UserController.userExists(accountType: accountScheme.accountName, credsId: credsId, userRepository: params.repos.user)
        switch userExists {
        case .doesNotExist:
            redeemSharingInvitationForNewUser(params:params, request: request, sharingInvitation: sharingInvitation, completion: completion)
        case .exists(let existingUser):
            redeemSharingInvitationForExistingUser(existingUser, params:params, request: request, sharingInvitation: sharingInvitation, completion: completion)
        case .error:
            let message = "Error looking up user!"
            Log.error(message)
            completion(.failure(.message(message)))
        }
    }
    
    private func redeemSharingInvitationForExistingUser(_ existingUser: User, params:RequestProcessingParameters, request: RedeemSharingInvitationRequest, sharingInvitation: SharingInvitation, completion: @escaping ((RequestProcessingParameters.Response)->())) {
    
        // Check to see if this user is already in this sharing group. We've got a lock on the sharing group, so no race condition will occur for adding user to sharing group.
        let key = SharingGroupUserRepository.LookupKey.primaryKeys(sharingGroupUUID: sharingInvitation.sharingGroupUUID, userId: existingUser.userId)
        let result = params.repos.sharingGroupUser.lookup(key: key, modelInit: SharingGroupUser.init)
        switch result {
        case .found:
            let message = "User id: \(existingUser.userId!) was already in sharing group: \(String(describing: sharingInvitation.sharingGroupUUID))"
            Log.error(message)
            completion(.failure(.message(message)))
            return
        case .noObjectFound:
            // Good: We can add this user to the sharing group.
            break
        case .error(let error):
            Log.error(error)
            completion(.failure(.message(error)))
            return
        }
        
        var owningUserId: UserId?
        
        guard let accountScheme = AccountScheme(.accountName(existingUser.accountType)) else {
            let message = "Could not look up AccountScheme from account type: \(String(describing: existingUser.accountType))"
            Log.error(message)
            completion(.failure(.message(message)))
            return
        }
        
        if accountScheme.userType == .sharing {
            owningUserId = sharingInvitation.owningUserId
        }

        guard case .success = params.repos.sharingGroupUser.add(sharingGroupUUID: sharingInvitation.sharingGroupUUID, userId: existingUser.userId, permission: sharingInvitation.permission, owningUserId: owningUserId) else {
            let message = "Failed on adding sharing group user for user."
            Log.error(message)
            completion(.failure(.message(message)))
            return
        }

        let response = RedeemSharingInvitationResponse()
        response.sharingGroupUUID = sharingInvitation.sharingGroupUUID
        response.userId = existingUser.userId
        
        completion(.success(response))
    }
    
    private func redeemSharingInvitationForNewUser(params:RequestProcessingParameters, request: RedeemSharingInvitationRequest, sharingInvitation: SharingInvitation, completion: @escaping ((RequestProcessingParameters.Response)->())) {
    
        guard let userProfile = params.userProfile else {
            let message = "Could not get userProfile!"
            Log.error(message)
            completion(.failure(.message(message)))
            return
        }
        
        guard var profileCreds = params.profileCreds else {
            let message = "Could not get profileCreds!"
            Log.error(message)
            completion(.failure(.message(message)))
            return
        }
        
        // No database creds because this is a new user-- so use params.profileCreds
        
        let user = User()
        user.username = userProfile.displayName
        
        guard let accountScheme = params.accountProperties?.accountScheme else {
            let message = "Could not get account scheme from properties!"
            Log.error(message)
            completion(.failure(.message(message)))
            return
        }
        
        user.accountType = accountScheme.accountName
        user.credsId = userProfile.id
        user.creds = profileCreds.toJSON()
        
        var createInitialOwningUserFile = false
        var owningUserId: UserId?

        switch accountScheme.userType {
        case .sharing:
            owningUserId = sharingInvitation.owningUserId
        case .owning:
            // When the user is an owning user, they will rely on their own cloud storage to upload new files-- for sharing groups where they have upload permissions.
            // Cloud storage folder must be present when redeeming an invitation: a) using an owning account, and where b) that owning account type needs a cloud storage folder (e.g., Google Drive). I'm not going to concern myself with the sharing permissions of the immediate sharing invitation because they may join other sharing groups-- and have write permissions there.
            if profileCreds.owningAccountsNeedCloudFolderName {
                guard let cloudFolderName = request.cloudFolderName else {
                    let message = "No cloud folder name given when redeeming sharing invitation using owning account that needs one!"
                    Log.error(message)
                    completion(.failure(.message(message)))
                    return
                }
                
                createInitialOwningUserFile = true
                user.cloudFolderName = cloudFolderName
            }
        }
        
        guard let userId = params.repos.user.add(user: user, accountManager: params.services.accountManager, accountDelegate: params.accountDelegate) else {
            let message = "Failed on adding sharing user to User!"
            Log.error(message)
            completion(.failure(.message(message)))
            return
        }
        
        guard case .success = params.repos.sharingGroupUser.add(sharingGroupUUID: sharingInvitation.sharingGroupUUID, userId: userId, permission: sharingInvitation.permission, owningUserId: owningUserId) else {
            let message = "Failed on adding sharing group user for new sharing user."
            Log.error(message)
            completion(.failure(.message(message)))
            return
        }

        let response = RedeemSharingInvitationResponse()
        response.sharingGroupUUID = sharingInvitation.sharingGroupUUID
        response.userId = userId
        
        // 11/5/17; Up until now I had been calling `generateTokensIfNeeded` for Facebook creds and that had been generating tokens. Somehow, in running my tests today, I'm getting failures from the Facebook API when I try to do this. This may only occur in testing because I'm passing long-lived access tokens. Plus, it's possible this error has gone undiagnosed until now. In testing, there is no need to generate the long-lived access tokens.

        profileCreds.accountCreationUser = .userId(userId)
        
        profileCreds.generateTokensIfNeeded(dbCreds: nil, routerResponse: params.routerResponse, success: {
            if createInitialOwningUserFile {
                // We're creating an account for an owning user. `profileCreds` will be an owning user account and this will implement the CloudStorage protocol.
                guard let cloudStorageCreds = profileCreds.cloudStorage(mock: params.services.mockStorage) else {
                    let message = "Could not obtain CloudStorage Creds"
                    Log.error(message)
                    completion(.failure(.message(message)))
                    return
                }
        
                UserController.createInitialFileForOwningUser(cloudFolderName: user.cloudFolderName, cloudStorage: cloudStorageCreds) { createResponse in
                    switch createResponse {
                    case .success:
                        completion(.success(response))
                        
                    case .accessTokenRevokedOrExpired:
                        // We're creating an account for an owning user. This is a fatal error-- we shouldn't have gotten to this point. Somehow authentication worked, but then a moment later the access token was revoked or expired.
                        let message = "Yikes: Access token expired or revoked. Fatal error."
                        Log.error(message)
                        completion(.failure(.message(message)))
                        
                    case .failure:
                        completion(.failure(nil))
                    }
                }
            }
            else {
                completion(.success(response))
            }
        }, failure: {
            completion(.failure(nil))
        })
    }
    
    func redeemSharingInvitation(params:RequestProcessingParameters) {
        assert(params.ep.authenticationLevel == .primary)

        guard let request = params.request as? RedeemSharingInvitationRequest else {
            let message = "Did not receive RedeemSharingInvitationRequest"
            Log.error(message)
            params.completion(.failure(.message(message)))
            return
        }
        
        // Remove stale invitations.
        let removalKey = SharingInvitationRepository.LookupKey.staleExpiryDates
        let removalResult = params.repos.sharing.retry {
            return params.repos.sharing.remove(key: removalKey)
        }
        guard case .removed(_) = removalResult else {
            let message = "Failed removing stale sharing invitations"
            Log.error(message)
            params.completion(.failure(.message(message)))
            return
        }

        // What I want to do at this point is to simultaneously and atomically, (a) lookup the sharing invitation, and (b) delete it. I believe that since (i) I'm using mySQL transactions, and (ii) InnoDb with a default transaction level of REPEATABLE READ, this should work by first doing the lookup, and then doing the delete.
        
        let sharingInvitationKey = SharingInvitationRepository.LookupKey.sharingInvitationUUID(uuid: request.sharingInvitationUUID)
        let lookupResult = params.repos.sharing.lookup(key: sharingInvitationKey, modelInit: SharingInvitation.init)
        
        guard case .found(let model) = lookupResult,
            let sharingInvitation = model as? SharingInvitation else {
                let message = "Could not find sharing invitation: \(String(describing: request.sharingInvitationUUID)). Was it stale?"
            Log.error(message)
            params.completion(.failure(.message(message)))
            return
        }
        
        redeem(params: params, request: request, sharingInvitation: sharingInvitation, sharingInvitationKey: sharingInvitationKey) { response in
            params.completion(response)
        }
    }
}
