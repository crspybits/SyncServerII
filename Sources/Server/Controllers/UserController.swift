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
        guard let addUserRequest = params.request as? AddUserRequest else {
            Log.error("Did not receive AddUserRequest")
            params.completion(nil)
            return
        }
        
        let userExists = UserController.userExists(userProfile: params.userProfile!, userRepository: params.repos.user)
        switch userExists {
        case .doesNotExist:
            break
        case .error, .exists(_):
            Log.error("Could not add user: Already exists!")
            params.completion(nil)
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
                Log.error("owningAccountsNeedCloudFolderName but no cloudFolderName")
                params.completion(nil)
                return
            }
            
            user.cloudFolderName = addUserRequest.cloudFolderName
        }
        
        guard params.profileCreds?.accountType.userType == .owning else {
            Log.error("Attempting to add a user with an Account that only allows sharing users!")
            params.completion(nil)
            return
        }
        
        guard let userId = params.repos.user.add(user: user) else {
            Log.error("Failed on adding user to User!")
            params.completion(nil)
            return
        }
        
        user.userId = userId

        guard case .success(let sharingGroupId) = params.repos.sharingGroup.add() else {
            Log.error("Failed on adding new sharing group.")
            params.completion(nil)
            return
        }

        guard case .success = params.repos.sharingGroupUser.add(sharingGroupId: sharingGroupId, userId: userId) else {
            Log.error("Failed on adding sharing group user.")
            params.completion(nil)
            return
        }
        
        if !params.repos.masterVersion.initialize(sharingGroupId: sharingGroupId) {
            Log.error("Failed on creating MasterVersion record for sharing group!")
            params.completion(nil)
            return
        }
        
        // Previously, we won't have established an `accountCreationUser` for these Creds-- because this is a new user.
        var profileCreds = params.profileCreds!
        profileCreds.accountCreationUser = .userId(userId, userType)
        
        let response = AddUserResponse()!
        response.userId = userId
        response.sharingGroupId = sharingGroupId
        
        // We're creating an account for an owning user. `profileCreds` will be an owning user account and this will implement the CloudStorage protocol.
        guard let cloudStorageCreds = profileCreds as? CloudStorage else {
            Log.error("Could not obtain CloudStorage Creds")
            params.completion(nil)
            return
        }
        
        Log.info("About to check if we need to generate tokens...")
        
        // I am not doing token generation earlier (e.g., in the RequestHandler) because in most cases, we don't have a user database record created earlier, so if needed cannot save the tokens generated.
        profileCreds.generateTokensIfNeeded(userType: userType, dbCreds: nil, routerResponse: params.routerResponse, success: {[unowned self] in
        
            if let fileName = Constants.session.owningUserAccountCreation.initialFileName,
                let fileContents = Constants.session.owningUserAccountCreation.initialFileContents,
                let data = fileContents.data(using: .utf8)  {
                
                self.createInitialFileForOwningUser(cloudFileName: fileName, cloudFolderName: addUserRequest.cloudFolderName, dataForFile: data, cloudStorage: cloudStorageCreds) { success in
                    if success {
                        params.completion(response)
                    }
                    else {
                        params.completion(nil)
                    }
                }
            }
            else {
                // Note: This is not an error-- the server just isn't configured to create these files for owning user accounts.
                Log.info("No file name and/or contents for initial user file.")
                params.completion(response)
            }
        }, failure: {
            params.completion(nil)
        })
    }
    
    func checkCreds(params:RequestProcessingParameters) {
        assert(params.ep.authenticationLevel == .secondary)
        
        let response = CheckCredsResponse()!
        response.userId = params.currentSignedInUser!.userId
        response.permission = params.currentSignedInUser!.permission
        
        // If we got this far, that means we passed primary and secondary authentication, but we also have to generate tokens, if needed.
        params.profileCreds!.generateTokensIfNeeded(userType: params.currentSignedInUser!.accountType.userType, dbCreds: params.creds!, routerResponse: params.routerResponse, success: {
            params.completion(response)
        }, failure: {
            params.completion(nil)
        })
    }
    
    // A user can only remove themselves, not another user-- this policy is enforced because the currently signed in user (with the UserProfile) is the one removed.
    // Not currently holding a lock to remove a user-- because currently our locks work on sharing groups-- and in general the scope of removing a user is wider than a single sharing group. In the worst case it seems that some other user(s), invited to join by the user being removed, could be uploading at the same time. Seems like limited consequences.
    func removeUser(params:RequestProcessingParameters) {
        assert(params.ep.authenticationLevel == .secondary)
        
        // I'm not going to remove the users files in their cloud storage. They own those. I think SyncServer doesn't have any business removing their files in this context.
        
        guard let accountType = AccountType.for(userProfile: params.userProfile!) else {
            Log.error("Could not get accountType!")
            params.completion(nil)
            return
        }
        
        let userRepoKey = UserRepository.LookupKey.accountTypeInfo(accountType: accountType, credsId: params.userProfile!.id)
        guard case .removed(let numberRows) = params.repos.user.remove(key: userRepoKey), numberRows == 1 else {
            Log.error("Could not remove user!")
            params.completion(nil)
            return
        }
        
        let uploadRepoKey = UploadRepository.LookupKey.userId(params.currentSignedInUser!.userId)        
        guard case .removed(_) = params.repos.upload.remove(key: uploadRepoKey) else {
            Log.error("Could not remove upload files for user!")
            params.completion(nil)
            return
        }
        
        // 6/25/18; Up until today, user removal had included actual removal of all of the user's files from the FileIndex. BUT-- this goes against how deletion occurs on the SyncServer-- we mark files as deleted, but don't actually remove them from the FileIndex.
        guard let _ = params.repos.fileIndex.markFilesAsDeleted(forUserId: params.currentSignedInUser!.userId) else {
            Log.error("Could not mark files as deleted for user!")
            params.completion(nil)
            return
        }
        
        // The user will no longer be part of any sharing groups
        let sharingGroupUserKey = SharingGroupUserRepository.LookupKey.userId(params.currentSignedInUser!.userId)
        switch params.repos.sharingGroupUser.remove(key: sharingGroupUserKey) {
        case .removed:
            break
        case .error(let error):
            Log.error("Could not remove sharing group references for user: \(error)")
            params.completion(nil)
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
            Log.error("Could not remove sharing invitations for user: \(error)")
            params.completion(nil)
            return
        }
        
        let response = RemoveUserResponse()!
        params.completion(response)
    }
}
