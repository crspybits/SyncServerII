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
            if accountType.accountScheme.userType == .owning {
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
            if newAccountType == accountType {
                assert(false)
            }
        }
        
        Log.info("Added account type to system: \(newAccountType)")
        accountTypes.append(newAccountType)
    }
    
    enum UpdateUserProfileError : Error {
        case noAccountWithThisToken
        case noTokenFoundInHeaders
    }
    
    // Account specific properties obtained from a request.
    struct AccountProperties {
        let accountScheme: AccountScheme
        let properties: [String: Any]
    }
    
    // Allow the specific Account's to process headers in their own special way, and get values from the request.
    // 7/14/19; Previously, I was using the UserProfile (from Kitura Credentials) to bridge these properties. However, that ran into crashes during load testing. See https://forums.swift.org/t/kitura-perfect-mysql-server-crash-double-free-or-corruption-prev/26740/10
    // So, I changed to using a thread-safe mechanism (AccountProperties).
    func getProperties(fromRequest request:RouterRequest) throws -> AccountProperties {
        guard let tokenTypeString = request.headers[ServerConstants.XTokenTypeKey] else {
            throw UpdateUserProfileError.noTokenFoundInHeaders
        }
        
        for accountType in accountTypes {
            if tokenTypeString == accountType.accountScheme.authTokenType {
                return AccountProperties(accountScheme: accountType.accountScheme, properties: accountType.getProperties(fromRequest: request))
            }
        }
        
        throw UpdateUserProfileError.noAccountWithThisToken
    }
    
    func accountFromProperties(properties: AccountProperties, user:AccountCreationUser?, delegate:AccountDelegate?) -> Account? {
        
        let currentAccountScheme = properties.accountScheme
        for accountType in accountTypes {
            if accountType.accountScheme == currentAccountScheme {
                return accountType.fromProperties(properties, user: user, delegate: delegate)
            }
        }
        
        return nil
    }
    
    func accountFromJSON(_ json:String, accountName name: AccountScheme.AccountName, user:AccountCreationUser, delegate:AccountDelegate?) throws -> Account? {
    
        for accountType in accountTypes {
            if accountType.accountScheme.accountName == name {
                return try accountType.fromJSON(json, user: user, delegate: delegate)
            }
        }
        
        Log.error("Could not find accountName: \(name)")
        
        return nil
    }
}
