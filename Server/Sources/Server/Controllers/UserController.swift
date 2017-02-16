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
        
        let userExists = UserController.userExists(userProfile: params.userProfile!, userRepository: params.repos.user)
        switch userExists {
        case .doesNotExist:
            break
        case .error, .exists(_):
            Log.error(message: "Could not add user: Already exists!")
            params.completion(nil)
            return
        }
        
        let user = User()
        user.username = params.userProfile!.displayName
        user.accountType = params.creds!.accountType
        user.credsId = params.userProfile!.id
        user.creds = params.creds!.toJSON()
        
        let userId = params.repos.user.add(user: user)
        if userId == nil {
            Log.error(message: "Failed on adding user to User!")
            params.completion(nil)
            return
        }
        
        if !params.repos.masterVersion.upsert(userId:userId!) {
            Log.error(message: "Failed on creating MasterVersion record for user!")
            params.completion(nil)
            return
        }
        
        let response = AddUserResponse()!
        params.completion(response)
    }
    
    func checkCreds(params:RequestProcessingParameters) {
        // We don't have to do anything here. It was already done prior to checkCreds being called because of:
        assert(ServerEndpoints.checkCreds.authenticationLevel == .secondary)
        
        let response = CheckCredsResponse()!
        params.completion(response)
    }
    
    // A user can only remove themselves, not another user-- this policy is enforced because the currently signed in user (with the UserProfile) is the one removed.
    func removeUser(params:RequestProcessingParameters) {
        assert(ServerEndpoints.removeUser.authenticationLevel == .secondary)
        
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
        
        if success == expectedSuccess {
            let response = RemoveUserResponse()!
            params.completion(response)
        }
        else {
            params.completion(nil)
        }
    }
}
