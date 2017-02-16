//
//  UserRepository.swift
//  Server
//
//  Created by Christopher Prince on 11/26/16.
//
//

import Foundation
import PerfectLib
import Credentials
import CredentialsGoogle

/* Data model v2 (with both OwningUser's and SharingUser's)
	{
		_id: (ObjectId), // userId: unique to the user (assigned by MongoDb).
 
		username: (String), // account name, e.g., email address.
        
        // The permissible userTypes for these account creds.
        // "OwningUser" and/or "SharingUser" in an array
        userTypes: [],
 
        accountType: // Value as follows

        // If userTypes includes "OwningUser", then the following options are available for accountType
        accountType: "Google",

         // If userTypes includes "SharingUser", then the following options are available for accountType
        accountType: "Facebook",

        creds: // Value as follows

        // If accountType is "Google"
        creds: {
            sub: XXXX, // Google individual identifier
            access_token: XXXX,
            refresh_token: XXXX
        }
        
        // If accountType is "Facebook"
        creds: {
            userId: String,
            
            // This is the last validated access token. It's stored so I don't have to do validation by going to Facebook's servers (see also https://stackoverflow.com/questions/37822004/facebook-server-side-access-token-validation-can-it-be-done-locally) 
            accessToken: String
        }
        
        // Users with SharingUser in their userTypes have another field in this structure:

        // The linked or shared "Owning User" accounts.
        // Array of structures because a given sharing user can potentially share more than one set of cloud storage data.
        linked: [
            { 
                // The _id of a PSUserCredentials object that must be an OwningUser
                owningUser: ObjectId,
            
                // See ServerConstants.sharingType
                sharingType: String
            }
        ]
	}
*/

class User : NSObject, Model {
    var userId: UserId!
    var username: String!
    
    let accountTypeKey = "accountType"
    var accountType: AccountType!

    // Account type specific id. E.g., for Google, this is the "sub".
    var credsId:String!
    
    let credsKey = "credsKey"
    var creds:String! // Stored as JSON
    
    // Converts from the current creds JSON and accountType
    var credsObject:Creds? {
        return Creds.toCreds(accountType: accountType, fromJSON: creds)
    }
    
    func typeConvertersToModel(propertyName:String) -> ((_ propertyValue:Any) -> Any?)? {
        switch propertyName {
            case accountTypeKey:
                return {(x:Any) -> Any? in
                    return AccountType(rawValue: x as! String)
                }
            default:
                return nil
        }
    }
}

class UserRepository : Repository {
    private(set) var db:Database!

    init(_ db:Database) {
        self.db = db
    }
    
    var tableName:String {
        return "User"
    }
    
    let usernameMaxLength = 255
    let credsIdMaxLength = 255
    let accountTypeMaxLength = 20
    
    func create() -> Database.TableCreationResult {
        let createColumns =
            "(userId BIGINT NOT NULL AUTO_INCREMENT, " +
            "username VARCHAR(\(usernameMaxLength)) NOT NULL," +
            
            "accountType VARCHAR(\(accountTypeMaxLength)) NOT NULL, " +
            
            "credsId VARCHAR(\(credsIdMaxLength)) NOT NULL, " +
        
            // Stored as JSON
            "creds TEXT NOT NULL, " +
            
            // I'm not going to require that the username be unique. The userId is unique.
            
            "UNIQUE (accountType, credsId), " +
            "UNIQUE (userId))"
        
        return db.createTableIfNeeded(tableName: "\(tableName)", columnCreateQuery: createColumns)
    }
    
    enum LookupKey : CustomStringConvertible {
        case userId(UserId)
        case accountTypeInfo(accountType:AccountType, credsId:String)
        
        var description : String {
            switch self {
            case .userId(let userId):
                return "userId(\(userId))"
            case .accountTypeInfo(accountType: let accountType, credsId: let credsId):
                return "accountTypeInfo(\(accountType), \(credsId))"
            }
        }
    }
    
    func lookupConstraint(key:LookupKey) -> String {
        switch key {
        case .userId(let userId):
            return "userId = '\(userId)'"
            
        case .accountTypeInfo(accountType: let accountType, credsId: let credsId):
            return "accountType = '\(accountType)' AND credsId = '\(credsId)'"
        }
    }
    
    // userId in the user model is ignored and the automatically generated userId is returned if the add is successful.
    func add(user:User) -> Int64? {
        if user.username == nil || user.accountType == nil || user.credsId == nil {
            Log.error(message: "One of the model values was nil!")
            return nil
        }
        
        // Validate the JSON before we insert it. Can't really do it in the setter for creds because it's
        guard let _ = Creds.toCreds(accountType: user.accountType, fromJSON: user.creds) else {
            Log.error(message: "Invalid creds JSON: \(user.creds)")
            return nil
        }
    
        let query = "INSERT INTO \(tableName) (username, accountType, credsId, creds) VALUES('\(user.username!)', '\(user.accountType!)', \(user.credsId!), '\(user.creds!)');"
        
        if db.connection.query(statement: query) {
            return db.connection.lastInsertId()
        }
        else {
            let error = db.error
            Log.error(message: "Could not insert into \(tableName): \(error)")
            return nil
        }
    }
    
    func updateCreds(creds newCreds:Creds, forUser user:User) -> Bool {
        // First need to merge creds-- otherwise, we might override part of the creds with our update.
    
        let oldCreds = user.credsObject!
        oldCreds.merge(withNewerCreds: newCreds)
        
        let query = "UPDATE \(tableName) SET creds = '\(oldCreds.toJSON()!)' WHERE " +
            lookupConstraint(key: .userId(user.userId))
        
        if db.connection.query(statement: query) {
            let numberUpdates = db.connection.numberAffectedRows()
            if numberUpdates == 1 {
                return true
            }
            else {
                Log.error(message: "Expected 1 update, but had \(numberUpdates)")
                return false
            }
        }
        else {
            let error = db.error
            Log.error(message: "Could not update row for \(tableName): \(error)")
            return false
        }
    }
}
