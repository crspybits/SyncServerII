//
//  UserController.swift
//  Server
//
//  Created by Christopher Prince on 11/26/16.
//
//

import LoggerAPI
import Credentials
import CredentialsGoogle
import SyncServerShared

class UserController : ControllerProtocol {
    // Don't do this setup in init so that database initalizations don't have to be done per endpoint call.
    class func setup() -> Bool {
        return true
    }
    
    init() {
    }
    
    enum UserStatus {
        case error
        case doesNotExist
        case exists(User)
    }
    
    // Looks up UserProfile in mySQL database.
    static func userExists(userProfile:UserProfile, userRepository:UserRepository) -> UserStatus {
        guard let accountType = AccountType.for(userProfile: userProfile) else {
            return .error
        }
        
        let result = userRepository.lookup(key: .accountTypeInfo(accountType:accountType, credsId:userProfile.id), modelInit: User.init)
        
        switch result {
        case .found(let object):
            let user = object as! User
            return .exists(user)
            
        case .noObjectFound:
            return .doesNotExist
            
        case .error(_):
            return .error
        }
    }
    
    func addUser(params:RequestProcessingParameters) {
        Log.debug("UserController.addUser.1")

        guard let addUserRequest = params.request as? AddUserRequest else {
            let message = "Did not receive AddUserRequest"
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
        
        // This necessarily is an owning user-- sharing users are created by the redeemSharingInvitation endpoint.
        let userType:UserType = .owning

        // No database creds because this is a new user-- so use params.profileCreds
        let user = User()
        user.username = params.userProfile!.displayName
        user.accountType = AccountType.for(userProfile: params.userProfile!)
        user.credsId = params.userProfile!.id
        user.creds = params.profileCreds!.toJSON(userType: userType)
        
        // This is creating the "root" owning user for a sharing group; they have max permissions.
        user.permission = .admin
        
        if params.profileCreds!.owningAccountsNeedCloudFolderName {
            guard addUserRequest.cloudFolderName != nil else {
                let message = "owningAccountsNeedCloudFolderName but no cloudFolderName"
                Log.error(message)
                params.completion(.failure(.message(message)))
                return
            }
            
            user.cloudFolderName = addUserRequest.cloudFolderName
        }
        
        guard params.profileCreds?.accountType.userType == .owning else {
            let message = "Attempting to add a user with an Account that only allows sharing users!"
            Log.error(message)
            params.completion(.failure(.message(message)))
            return
        }
        
        guard let userId = params.repos.user.add(user: user) else {
            let message = "Failed on adding user to User!"
            Log.error(message)
            params.completion(.failure(.message(message)))
            return
        }
        
        user.userId = userId

        guard case .success(let sharingGroupId) = params.repos.sharingGroup.add() else {
            let message = "Failed on adding new sharing group."
            Log.error(message)
            params.completion(.failure(.message(message)))
            return
        }

        guard case .success = params.repos.sharingGroupUser.add(sharingGroupId: sharingGroupId, userId: userId) else {
            let message = "Failed on adding sharing group user."
            Log.error(message)
            params.completion(.failure(.message(message)))
            return
        }
        
        if !params.repos.masterVersion.initialize(sharingGroupId: sharingGroupId) {
            let message = "Failed on creating MasterVersion record for sharing group!"
            Log.error(message)
            params.completion(.failure(.message(message)))
            return
        }
        
        let response = AddUserResponse()!
        response.userId = userId
        response.sharingGroupId = sharingGroupId
        
        // Previously, we won't have established an `accountCreationUser` for these Creds-- because this is a new user.
        var profileCreds = params.profileCreds!
        profileCreds.accountCreationUser = .userId(userId, userType)

        // We're creating an account for an owning user. `profileCreds` will be an owning user account and this will implement the CloudStorage protocol.
        guard let cloudStorageCreds = profileCreds as? CloudStorage else {
            let message = "Could not obtain CloudStorage Creds"
            Log.error(message)
            params.completion(.failure(.message(message)))
            return
        }
        
        Log.info("About to check if we need to generate tokens...")
        
        // I am not doing token generation earlier (e.g., in the RequestHandler) because in most cases, we don't have a user database record created earlier, so if needed cannot save the tokens generated.
        profileCreds.generateTokensIfNeeded(userType: userType, dbCreds: nil, routerResponse: params.routerResponse, success: {
        
            UserController.createInitialFileForOwningUser(cloudFolderName: addUserRequest.cloudFolderName, cloudStorage: cloudStorageCreds) { success in
                if success {
                    params.completion(.success(response))
                }
                else {
                    params.completion(.failure(nil))
                }
            }
        }, failure: {
            params.completion(.failure(nil))
        })
    }
    
    func checkCreds(params:RequestProcessingParameters) {
        assert(params.ep.authenticationLevel == .secondary)
        
        let response = CheckCredsResponse()!
        response.userId = params.currentSignedInUser!.userId
        response.permission = params.currentSignedInUser!.permission
        
        // If we got this far, that means we passed primary and secondary authentication, but we also have to generate tokens, if needed.
        params.profileCreds!.generateTokensIfNeeded(userType: params.currentSignedInUser!.accountType.userType, dbCreds: params.creds!, routerResponse: params.routerResponse, success: {
            params.completion(.success(response))
        }, failure: {
            params.completion(.failure(nil))
        })
    }
    
    // A user can only remove themselves, not another user-- this policy is enforced because the currently signed in user (with the UserProfile) is the one removed.
    // Not currently holding a lock to remove a user-- because currently our locks work on sharing groups-- and in general the scope of removing a user is wider than a single sharing group. In the worst case it seems that some other user(s), invited to join by the user being removed, could be uploading at the same time. Seems like limited consequences.
    func removeUser(params:RequestProcessingParameters) {
        assert(params.ep.authenticationLevel == .secondary)
        
        // I'm not going to remove the users files in their cloud storage. They own those. I think SyncServer doesn't have any business removing their files in this context.
        
        guard let accountType = AccountType.for(userProfile: params.userProfile!) else {
            let message = "Could not get accountType!"
            Log.error(message)
            params.completion(.failure(.message(message)))
            return
        }
        
        let deviceUUIDRepoKey = DeviceUUIDRepository.LookupKey.userId(params.currentSignedInUser!.userId)
        guard case .removed(_) = params.repos.deviceUUID.remove(key: deviceUUIDRepoKey) else {
            let message = "Could not remove deviceUUID's for user!"
            Log.error(message)
            params.completion(.failure(.message(message)))
            return
        }
        
        guard params.repos.user.resetOwningUserIds(forUserId: params.currentSignedInUser!.userId) else {
            let message = "Could not reset owningUserId's of other users."
            Log.error(message)
            params.completion(.failure(.message(message)))
            return
        }
        
        // When deleting a user, should set to NULL any sharing users that have that userId (being deleted) as their owningUserId.
        
        let uploadRepoKey = UploadRepository.LookupKey.userId(params.currentSignedInUser!.userId)        
        guard case .removed(_) = params.repos.upload.remove(key: uploadRepoKey) else {
            let message = "Could not remove upload files for user!"
            Log.error(message)
            params.completion(.failure(.message(message)))
            return
        }
        
        // 6/25/18; Up until today, user removal had included actual removal of all of the user's files from the FileIndex. BUT-- this goes against how deletion occurs on the SyncServer-- we mark files as deleted, but don't actually remove them from the FileIndex.
        guard let _ = params.repos.fileIndex.markFilesAsDeleted(forUserId: params.currentSignedInUser!.userId) else {
            let message = "Could not mark files as deleted for user!"
            Log.error(message)
            params.completion(.failure(.message(message)))
            return
        }
        
        // The user will no longer be part of any sharing groups
        let sharingGroupUserKey = SharingGroupUserRepository.LookupKey.userId(params.currentSignedInUser!.userId)
        switch params.repos.sharingGroupUser.remove(key: sharingGroupUserKey) {
        case .removed:
            break
        case .error(let error):
            let message = "Could not remove sharing group references for user: \(error)"
            Log.error(message)
            params.completion(.failure(.message(message)))
            return
        }
        
        // A sharing user that was invited by this user that is deleting themselves will no longer be able to upload files. Because those files have nowhere to go. However, they should still be able to read files in the sharing group uploaded by others. See https://github.com/crspybits/SyncServerII/issues/78
        
        // When removing an owning user: Also remove any sharing invitations that have that owning user in them-- this is just in case there are non-expired invitations from that sharing user. They will be invalid now.
        let sharingInvitationsKey = SharingInvitationRepository.LookupKey
            .owningUserId(params.currentSignedInUser!.userId)
        switch params.repos.sharing.remove(key: sharingInvitationsKey) {
        case .removed:
            break
        case .error(let error):
            let message = "Could not remove sharing invitations for user: \(error)"
            Log.error(message)
            params.completion(.failure(.message(message)))
            return
        }
        
        // This has to be last-- we have to remove all references to the user first-- due to foreign key constraints.
        let userRepoKey = UserRepository.LookupKey.accountTypeInfo(accountType: accountType, credsId: params.userProfile!.id)
        guard case .removed(let numberRows) = params.repos.user.remove(key: userRepoKey), numberRows == 1 else {
            let message = "Could not remove user!"
            Log.error(message)
            params.completion(.failure(.message(message)))
            return
        }
        
        let response = RemoveUserResponse()!
        params.completion(.success(response))
    }
}
