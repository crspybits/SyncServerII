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
        
        let result = UserRepository.lookup(key: .accountTypeInfo(accountType:accountType, credsId:userProfile.id))
        
        switch result {
        case .found(let user):
            return .exists(user)
            
        case .noUserFound:
            return .doesNotExist
            
        case .error(_):
            return .error
        }
    }
    
    func addUser(_ request: RequestMessage, creds:Creds?, profile:UserProfile?) -> AddUserResponse? {
        
        let userExists = UserController.userExists(userProfile: profile!)
        switch userExists {
        case .doesNotExist:
            break
        case .error, .exists(_):
            Log.error(message: "Could not add user: Already exists!")
            return nil
        }
        
        let user = User()
        user.username = profile!.displayName
        user.accountType = creds!.accountType
        user.credsId = profile!.id
        user.creds = creds!.toJSON()
        
        let userId = UserRepository.add(user: user)
        if userId == nil {
            Log.error(message: "Failed on adding user to User!")
            return nil
        }

        let response = AddUserResponse()
        response.result = "success"
        return response
    }
    
    func checkCreds(_ request: RequestMessage, creds:Creds?, profile:UserProfile?) -> CheckCredsResponse? {
        // We don't have to do anything here. It was already done prior to checkCreds being called because of:
        assert(ServerEndpoints.checkCreds.authenticationLevel == .secondary)
        
        let response = CheckCredsResponse()
        response.result = "Success"
        return response
    }
    
    // A user can only remove themselves, not another user-- this policy is enforced because the currently signed in user (with the UserProfile) is the one removed.
    func removeUser(_ request: RequestMessage, creds:Creds?, profile:UserProfile?) -> RemoveUserResponse? {
        assert(ServerEndpoints.removeUser.authenticationLevel == .secondary)
        
        if case .removed = UserRepository.remove(user: .accountTypeInfo(accountType: creds!.accountType, credsId: profile!.id)) {
            let response = RemoveUserResponse()
            response.result = "Success"
            return response
        }
        else {
            return nil
        }
    }
}
