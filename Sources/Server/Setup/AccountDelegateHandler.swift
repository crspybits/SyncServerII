//
//  AccountDelegateHandler.swift
//  Server
//
//  Created by Christopher G Prince on 12/7/18.
//

import Foundation
import LoggerAPI
import ServerAccount

class AccountDelegateHandler: AccountDelegate {
    private let userRepository: UserRepository
    
    init(userRepository: UserRepository) {
        self.userRepository = userRepository
    }
    
    func saveToDatabase(account creds:Account) -> Bool {
        let result = userRepository.updateCreds(creds: creds, forUser: creds.accountCreationUser!)
        Log.debug("saveToDatabase: result: \(result)")
        return result
    }
}
