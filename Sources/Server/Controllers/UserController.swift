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
    class func setup(db:Database) -> Bool {
        if case .failure(_) = UserRepository(db).upcreate() {
            return false
        }
        
        if case .failure(_) = MasterVersionRepository(db).upcreate() {
            return false
        }
        
        if case .failure(_) = DeviceUUIDRepository(db).upcreate() {
            return false
        }

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
        user.userType = userType
        
        if params.profileCreds!.owningAccountsNeedCloudFolderName {
            user.cloudFolderName = addUserRequest.cloudFolderName
        }
        
        guard params.profileCreds!.signInType.contains(.owningUser) else {
            Log.error("Attempting to add a user with an Account that only allows sharing users!")
            params.completion(nil)
            return
        }
        
        let userId = params.repos.user.add(user: user)
        if userId == nil {
            Log.error("Failed on adding user to User!")
            params.completion(nil)
            return
        }
        
        user.userId = userId
        
        if !params.repos.masterVersion.initialize(userId:userId!) {
            Log.error("Failed on creating MasterVersion record for user!")
            params.completion(nil)
            return
        }
        
        // Previously, we won't have established an `accountCreationUser` for these Creds-- because this is a new user.
        var profileCreds = params.profileCreds!
        profileCreds.accountCreationUser = .userId(userId!, userType)
        
        let response = AddUserResponse()!
        response.userId = userId
        
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

        let sharingUser = params.currentSignedInUser!.userType == .sharing
        
        let response = CheckCredsResponse()!
        response.userId = params.currentSignedInUser!.userId
        
        if sharingUser {
            response.sharingPermission = params.currentSignedInUser!.sharingPermission
        }
        
        // If we got this far, that means we passed primary and secondary authentication, but we also have to generate tokens, if needed.
        params.profileCreds!.generateTokensIfNeeded(userType: params.currentSignedInUser!.userType, dbCreds: params.creds!, routerResponse: params.routerResponse, success: {
            params.completion(response)
        }, failure: {
            params.completion(nil)
        })
    }
    
    // A user can only remove themselves, not another user-- this policy is enforced because the currently signed in user (with the UserProfile) is the one removed.
    func removeUser(params:RequestProcessingParameters) {
        assert(params.ep.authenticationLevel == .secondary)
        
        var success = 0
        let expectedSuccess = 5
        
        // We'll just do each of the removals, not checking for error after each. Since this is done on the basis of a db transaction, we'll be rolling back if there is an error in any case.
        
        // I'm not going to remove the users files in their cloud storage. They own those. I think I don't have any business removing their files in this context.
        
        guard let accountType = AccountType.for(userProfile: params.userProfile!) else {
            Log.error("Could not get accountType!")
            params.completion(nil)
            return
        }
        
        let userRepoKey = UserRepository.LookupKey.accountTypeInfo(accountType: accountType, credsId: params.userProfile!.id)
        if case .removed(let numberRows) = params.repos.user.remove(key: userRepoKey) {
            if numberRows == 1 {
                success += 1
            }
        }
        
        let uploadRepoKey = UploadRepository.LookupKey.userId(params.currentSignedInUser!.userId)        
        if case .removed(_) = params.repos.upload.remove(key: uploadRepoKey) {
            success += 1
        }
        
        let masterVersionRepKey = MasterVersionRepository.LookupKey.userId(params.currentSignedInUser!.userId)
        if case .removed(_) = params.repos.masterVersion.remove(key: masterVersionRepKey) {
            success += 1
        }
        
        let lockRepoKey = LockRepository.LookupKey.userId(params.currentSignedInUser!.userId)
        if case .removed(_) = params.repos.lock.remove(key: lockRepoKey) {
            success += 1
        }
        
        let fileIndexRepoKey = FileIndexRepository.LookupKey.userId(params.currentSignedInUser!.userId)
        if case .removed(_) = params.repos.fileIndex.remove(key: fileIndexRepoKey) {
            success += 1
        }
        
        // TODO: *2* When removing an owning user, check to see if that owning user has users sharing their data. If so, it would seem best to also remove those sharing users-- because why should a user be allowed to share someone's data when that someone is no longer on the system?
        
        // TODO: *2* When removing an owning user: Also remove any sharing invitations that have that owning user in them.
        
        if success == expectedSuccess {
            let response = RemoveUserResponse()!
            params.completion(response)
        }
        else {
            params.completion(nil)
        }
    }
}
