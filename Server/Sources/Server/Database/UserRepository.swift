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
    var userId: Int64!
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
    private static let tableName = "User"
    static let usernameMaxLength = 255
    static let credsIdMaxLength = 255
    
    static func create() -> Database.TableCreationResult {
        let createColumns =
            "(userId BIGINT NOT NULL AUTO_INCREMENT, " +
            "username VARCHAR(\(usernameMaxLength)) NOT NULL," +
            
            "accountType VARCHAR(20) NOT NULL, " +
            
            "credsId VARCHAR(\(credsIdMaxLength)) NOT NULL, " +
        
            // Stored as JSON
            "creds TEXT NOT NULL, " +
            
            // I'm not going to require that the username be unique. The userId is unique.
            
            "UNIQUE (accountType, credsId), " +
            "UNIQUE (userId))"
        
        return Database.session.createTableIfNeeded(tableName: "\(tableName)", columnCreateQuery: createColumns)
    }
    
    // Remove entire table.
    static func remove() -> Bool {
        return Database.session.connection.query(statement: "DROP TABLE \(tableName)")
    }
    
    enum LookupResult {
        case found(User)
        case noUserFound
        case error(String)
    }
    
    enum LookupKey : CustomStringConvertible {
        case userId(Int64)
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
    
    private static func lookupConstraint(key:LookupKey) -> String {
        switch key {
        case .userId(let userId):
            return "userId = '\(userId)'"
            
        case .accountTypeInfo(accountType: let accountType, credsId: let credsId):
            return "accountType = '\(accountType)' AND credsId = '\(credsId)'"
        }
    }
    
    static func lookup(key:LookupKey) -> LookupResult {
        let userQuery = "select * from \(tableName) where " + lookupConstraint(key: key)
        let select = Select(query: userQuery, modelInit: User.init, ignoreErrors:false)
        
        switch select.numberResultRows() {
        case 0:
            return .noUserFound
            
        case 1:
            var result:User!
            select.forEachRow { rowModel in
                result = rowModel as! User
            }
            
            if select.forEachRowStatus != nil {
                let error = "Error: \(select.forEachRowStatus!) in Select forEachRow"
                Log.error(message: error)
                return .error(error)
            }
            
            return .found(result)

        default:
            let error = "Error: \(select.numberResultRows()) in Select result: More than one user for credentials!"
            Log.error(message: error)
            return .error(error)
        }
    }
    
    // userId in the user model is ignored and the automatically generated userId is returned if the add is successful.
    static func add(user:User) -> Int64? {
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
        
        if Database.session.connection.query(statement: query) {
            return Database.session.connection.lastInsertId()
        }
        else {
            let error = Database.session.error
            Log.error(message: "Could not add user: \(error)")
            return nil
        }
    }
    
    static func updateCreds(creds newCreds:Creds, forUser user:User) -> Bool {
        // First need to merge creds-- otherwise, we might override part of the creds with our update.
    
        let oldCreds = user.credsObject!
        oldCreds.merge(withNewerCreds: newCreds)
        
        let query = "UPDATE \(tableName) SET creds = '\(oldCreds.toJSON())' WHERE " +
            lookupConstraint(key: .userId(user.userId))
        
        if Database.session.connection.query(statement: query) {
            // TODO: Make sure only a single row was affected.
            return true
        }
        else {
            let error = Database.session.error
            Log.error(message: "Could not add user: \(error)")
            return false
        }
    }
    
    enum RemoveResult {
        case removed
        case error(String)
    }
    
    static func remove(user key:LookupKey) -> RemoveResult {
        let query = "delete from \(tableName) where " + lookupConstraint(key: key)
        
        if Database.session.connection.query(statement: query) {
            // TODO: Ensure that only a single row was affected.
            Log.info(message: "Successfully removed user: \(key)")
            return .removed
        }
        else {
            let error = Database.session.error
            Log.error(message: "Could not remove user: \(error)")
            return .error("\(error)")
        }
    }
}
