//
//  AccountManager.swift
//  Server
//
//  Created by Christopher Prince on 7/9/17.
//

import Foundation
import Credentials
import Kitura
import SyncServerShared

class AccountManager {
    static let session = AccountManager()
    private var accountTypes = [Account.Type]()
    
    private init() {
    }
    
    func addAccountType(_ newAccountType:Account.Type) {
        for accountType in accountTypes {
            // Don't add the same account type twice!
            if newAccountType.accountType.toAuthTokenType() == accountType.accountType.toAuthTokenType() {
                assert(false)
            }
        }
        
        accountTypes.append(newAccountType)
    }
    
    enum UpdateUserProfileResult {
        case success
        case noAccountWithThisToken
        case noTokenFoundInHeaders
        case badTokenFoundInHeaders
    }
    
    // Allow the specific Account's to process headers in their own special way, and modify the UserProfile accordingly if they need to.
    func updateUserProfile(_ userProfile:UserProfile, fromRequest request:RouterRequest) -> UpdateUserProfileResult {
        guard let tokenTypeString = request.headers[ServerConstants.XTokenTypeKey] else {
            return .noTokenFoundInHeaders
        }
        
        guard let tokenType = ServerConstants.AuthTokenType(rawValue: tokenTypeString) else {
            return .badTokenFoundInHeaders
        }
        
        for accountType in accountTypes {
            if tokenType == accountType.accountType.toAuthTokenType() {
                accountType.updateUserProfile(userProfile, fromRequest: request)
                return .success
            }
        }
        
        return .noAccountWithThisToken
    }
    
    func accountFromProfile(profile:UserProfile, user:AccountCreationUser?, delegate:AccountDelegate?) -> Account? {
        
        let specificAccountToken = ServerConstants.AuthTokenType.GoogleToken
        for accountType in accountTypes {
            if accountType.accountType.toAuthTokenType() == specificAccountToken {
                // TODO!!: Complete this!
            }
        }
        
        return nil
    }
    
    func accountFromJSON(_ json:String, accountType: AccountType, user:AccountCreationUser?, delegate:AccountDelegate?) throws -> Account? {
        return nil
    }
}
