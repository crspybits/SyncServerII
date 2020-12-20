//
//  UserRepository+AccountDelegate.swift
//  Server
//
//  Created by Christopher G Prince on 12/19/20.
//

import Foundation
import ServerAccount
import LoggerAPI

extension UserRepository {
    class AccountDelegateHandler: AccountDelegate {
        let userRepository: UserRepository
        let accountManager: AccountManager
        
        init(userRepository: UserRepository, accountManager: AccountManager) {
            self.userRepository = userRepository
            self.accountManager = accountManager
        }
        
        func saveToDatabase(account creds:Account) -> Bool {
            guard let accountCreationUser = creds.accountCreationUser else {
                Log.error("saveToDatabase: Could not get accountCreationUser")
                return false
            }

            let result = userRepository.updateCreds(creds: creds, forUser: accountCreationUser, accountManager: accountManager)
            Log.debug("saveToDatabase: result: \(result)")
            return result
        }
    }
}

