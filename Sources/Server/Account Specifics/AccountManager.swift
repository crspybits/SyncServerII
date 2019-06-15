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
import LoggerAPI

class AccountManager {
    static let session = AccountManager()
    private var accountTypes = [Account.Type]()
    
    var numberAccountTypes: Int {
        return accountTypes.count
    }
    
    // Number of account types that can own.
    var numberOfOwningAccountTypes:Int {
        var number = 0
        
        for accountType in accountTypes {
            if accountType.accountType.userType == .owning {
                number += 1
            }
        }
        
        return number
    }
    
    private init() {
    }
    
    func reset() {
        accountTypes.removeAll()
    }
    
    // I'm allowing these to be added dynamically to enable the user of the server to disallow certain types of account credentials.
    func addAccountType(_ newAccountType:Account.Type) {
        for accountType in accountTypes {
            // Don't add the same account type twice!
            if newAccountType.accountType.toAuthTokenType() == accountType.accountType.toAuthTokenType() {
                assert(false)
            }
        }
        
        Log.info("Added account type to system: \(newAccountType)")
        accountTypes.append(newAccountType)
    }
    
    enum UpdateUserProfileError : Error {
        case noAccountWithThisToken
        case noTokenFoundInHeaders
        case badTokenFoundInHeaders
    }
    
    // Allow the specific Account's to process headers in their own special way, and modify the UserProfile accordingly if they need to. Must be called at the very start of request processing.
    func updateUserProfile(_ userProfile:UserProfile, fromRequest request:RouterRequest) throws {
        guard let tokenTypeString = request.headers[ServerConstants.XTokenTypeKey] else {
            throw UpdateUserProfileError.noTokenFoundInHeaders
        }
        
        guard let tokenType = ServerConstants.AuthTokenType(rawValue: tokenTypeString) else {
            throw UpdateUserProfileError.badTokenFoundInHeaders
        }
        
        let accountType = AccountType.fromAuthTokenType(tokenType)
        userProfile.extendedProperties[SyncServerAccountType] = accountType.rawValue
        
        for accountType in accountTypes {
            if tokenType == accountType.accountType.toAuthTokenType() {
                accountType.updateUserProfile(userProfile, fromRequest: request)
                return
            }
        }
        
        throw UpdateUserProfileError.noAccountWithThisToken
    }
    
    func accountFromProfile(profile:UserProfile, user:AccountCreationUser?, delegate:AccountDelegate?) -> Account? {
        
        let currentAccountType = AccountType.for(userProfile: profile)
        for accountType in accountTypes {
            if accountType.accountType == currentAccountType {
                return accountType.fromProfile(profile: profile, user: user, delegate: delegate)
            }
        }
        
        return nil
    }
    
    func accountFromJSON(_ json:String, accountType type: AccountType, user:AccountCreationUser, delegate:AccountDelegate?) throws -> Account? {
    
        for accountType in accountTypes {
            if accountType.accountType == type {
                return try accountType.fromJSON(json, user: user, delegate: delegate)
            }
        }
        
        Log.error("Could not find accountType: \(type)")
        
        return nil
    }
}
