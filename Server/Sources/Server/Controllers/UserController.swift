//
//  UserController.swift
//  Server
//
//  Created by Christopher Prince on 11/26/16.
//
//

import PerfectLib
import Credentials
import CredentialsGoogle

class UserController : ControllerProtocol {
    // Don't do this setup in init so that database initalizations don't have to be done per endpoint call.
    class func setup(db:Database) -> Bool {
        if case .failure(_) = UserRepository(db).create() {
            return false
        }
        
        if case .failure(_) = MasterVersionRepository(db).create() {
            return false
        }
        
        if case .failure(_) = DeviceUUIDRepository(db).create() {
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
        guard let accountType = AccountType.fromSpecificCredsType(specificCreds: userProfile.accountSpecificCreds!) else {
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
        // TODO: *0* Should this still be marked as `generateTokens`? We're generating the tokens locally, in this method.
        assert(params.ep.generateTokens)

        let userExists = UserController.userExists(userProfile: params.userProfile!, userRepository: params.repos.user)
        switch userExists {
        case .doesNotExist:
            break
        case .error, .exists(_):
            Log.error(message: "Could not add user: Already exists!")
            params.completion(nil)
            return
        }
        
        // No database creds because this is a new user-- so use params.profileCreds
        
        let user = User()
        user.username = params.userProfile!.displayName
        user.accountType = params.profileCreds!.accountType
        user.credsId = params.userProfile!.id
        user.creds = params.profileCreds!.toJSON()
        
        // This necessarily is an owning user-- sharing users are created by the redeemSharingInvitation endpoint. This user must also be using Google creds.
        user.userType = .owning
        
        // TODO: *5* Remove this restriction when we add Dropbox or other cloud storage services.
        guard params.profileCreds!.accountType == .Google else {
            Log.error(message: "Owning users must currently be using Google creds!")
            return
        }
        
        let userId = params.repos.user.add(user: user)
        if userId == nil {
            Log.error(message: "Failed on adding user to User!")
            params.completion(nil)
            return
        }
        
        user.userId = userId
        
        if !params.repos.masterVersion.initialize(userId:userId!) {
            Log.error(message: "Failed on creating MasterVersion record for user!")
            params.completion(nil)
            return
        }
        
        // Previously, we won't have established a CredsUser for these Creds-- because this is a new user.
        params.profileCreds!.user = .userId(userId!)
        
        params.profileCreds!.generateTokens() { successGeneratingTokens, error in
            guard error == nil else {
                Log.error(message: "Failed attempting to generate tokens: \(error)")
                params.completion(nil)
                return
            }
            
            let response = AddUserResponse()!
            params.completion(response)
        }
    }
    
    func checkCreds(params:RequestProcessingParameters) {
        assert(params.ep.authenticationLevel == .secondary)

        // If we got this far, that means we passed primary and secondary authentication, but we also have to generate tokens, if needed.
        assert(params.ep.generateTokens)
        
        if params.profileCreds!.needToGenerateTokens(dbCreds: params.creds!) {
            params.profileCreds!.generateTokens() { successGeneratingTokens, error in
                if error == nil {
                    let response = CheckCredsResponse()!
                    params.completion(response)
                }
                else {
                    Log.error(message: "Failed attempting to generate tokens: \(error)")
                    params.completion(nil)
                }
            }
        }
        
        let response = CheckCredsResponse()!
        params.completion(response)
    }
    
    // A user can only remove themselves, not another user-- this policy is enforced because the currently signed in user (with the UserProfile) is the one removed.
    func removeUser(params:RequestProcessingParameters) {
        assert(params.ep.authenticationLevel == .secondary)
        
        var success = 0
        let expectedSuccess = 5
        
        // We'll just do each of the removals, not checking for error after each. Since this is done on the basis of a db transaction, we'll be rolling back if there is an error in any case.
        
        // I'm not going to remove the users files in their cloud storage. They own those. I think I don't have any business removing their files in this context.
        
        let userRepoKey = UserRepository.LookupKey.accountTypeInfo(accountType: params.creds!.accountType, credsId: params.userProfile!.id)
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
