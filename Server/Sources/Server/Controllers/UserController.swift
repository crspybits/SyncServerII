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
    class func setup() -> Bool {
        if case .failure(_) = UserRepository.create() {
            return false
        }
        
        if case .failure(_) = MasterVersionRepository.create() {
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
    static func userExists(userProfile:UserProfile) -> UserStatus {
        guard let accountType = AccountType.fromSpecificCredsType(specificCreds: userProfile.accountSpecificCreds!) else {
            return .error
        }
        
        let result = UserRepository.lookup(key: .accountTypeInfo(accountType:accountType, credsId:userProfile.id), modelInit: User.init)
        
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
    
    func addUser(request: RequestMessage, creds: Creds?, profile: UserProfile?,
        completion: @escaping (ResponseMessage?)->()) {
        
        let userExists = UserController.userExists(userProfile: profile!)
        switch userExists {
        case .doesNotExist:
            break
        case .error, .exists(_):
            Log.error(message: "Could not add user: Already exists!")
            completion(nil)
            return
        }
        
        let user = User()
        user.username = profile!.displayName
        user.accountType = creds!.accountType
        user.credsId = profile!.id
        user.creds = creds!.toJSON()
        
        let userId = UserRepository.add(user: user)
        if userId == nil {
            Log.error(message: "Failed on adding user to User!")
            completion(nil)
            return
        }
        
        if !MasterVersionRepository.upsert(userId:userId!) {
            Log.error(message: "Failed on creating MasterVersion record for user!")
            completion(nil)
            return
        }
        
        let response = AddUserResponse()!
        response.result = "success"
        completion(response)
    }
    
    func checkCreds(request: RequestMessage, creds: Creds?, profile: UserProfile?,
        completion: @escaping (ResponseMessage?)->()) {
        // We don't have to do anything here. It was already done prior to checkCreds being called because of:
        assert(ServerEndpoints.checkCreds.authenticationLevel == .secondary)
        
        let response = CheckCredsResponse()!
        response.result = "Success"
        completion(response)
    }
    
    // A user can only remove themselves, not another user-- this policy is enforced because the currently signed in user (with the UserProfile) is the one removed.
    func removeUser(request: RequestMessage, creds: Creds?, profile: UserProfile?,
        completion: @escaping (ResponseMessage?)->()) {
        assert(ServerEndpoints.removeUser.authenticationLevel == .secondary)
        
        var success = 0
        let expectedSuccess = 5
        
        // We'll just do each of the removals, not checking for error after each. Since this is done on the basis of a db transaction, we'll be rolling back if there is an error in any case.
        
        // I'm not going to remove the users files in their cloud storage. They own those. I think I don't have any business removing their files in this context.
        
        let userRepoKey = UserRepository.LookupKey.accountTypeInfo(accountType: creds!.accountType, credsId: profile!.id)
        if case .removed(let numberRows) = UserRepository.remove(key: userRepoKey) {
            if numberRows == 1 {
                success += 1
            }
        }
        
        let uploadRepoKey = UploadRepository.LookupKey.userId(SignedInUser.session.current!.userId)
        if case .removed(_) = UploadRepository.remove(key: uploadRepoKey) {
            success += 1
        }
        
        let masterVersionRepKey = MasterVersionRepository.LookupKey.userId(SignedInUser.session.current!.userId)
        if case .removed(_) = MasterVersionRepository.remove(key: masterVersionRepKey) {
            success += 1
        }
        
        let lockRepoKey = LockRepository.LookupKey.userId(SignedInUser.session.current!.userId)
        if case .removed(_) = LockRepository.remove(key: lockRepoKey) {
            success += 1
        }
        
        let fileIndexRepoKey = FileIndexRepository.LookupKey.userId(SignedInUser.session.current!.userId)
        if case .removed(_) = FileIndexRepository.remove(key: fileIndexRepoKey) {
            success += 1
        }
        
        if success == expectedSuccess {
            let response = RemoveUserResponse()!
            response.result = "Success"
            completion(response)
        }
        else {
            completion(nil)
        }
    }
}
