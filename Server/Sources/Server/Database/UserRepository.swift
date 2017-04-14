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

enum UserType : String {
    case sharing // user is sharing data
    case owning // user owns the data

    static func maxStringLength() -> Int {
        return max(UserType.sharing.rawValue.characters.count, UserType.owning.rawValue.characters.count)
    }
}

class User : NSObject, Model {
    var userId: UserId!
    var username: String!
    
    // A given user on the system can only have a single UserType role, i.e., either an owning user or a sharing user.
    static let userTypeKey = "userType"
    var userType:UserType!
    
    // Only when the current user is a sharing user, this gives the userId that is the owner of the data.
    var owningUserId:UserId?

    // Only when the current user is a sharing user, this gives the permission that the sharing user has to the owning users data.
    static let sharingPermissionKey = "sharingPermission"
    var sharingPermission:SharingPermission?
    
    static let accountTypeKey = "accountType"
    var accountType: AccountType!

    // Account type specific id. E.g., for Google, this is the "sub".
    var credsId:String!
    
    let credsKey = "credsKey"
    var creds:String! // Stored as JSON
    
    var effectiveOwningUserId:UserId {
        if userType == .sharing {
            return owningUserId!
        }
        else {
            return userId
        }
    }
    
    // Converts from the current creds JSON and accountType. Returns a new `Creds` object with each call.
    var credsObject:Creds? {
        do {
            let credsObj = try Creds.toCreds(accountType: accountType, fromJSON: creds, user: .user(self), delegate:nil)
            return credsObj
        }
        catch (let error) {
            Log.error(message: "\(error)")
            return nil
        }
    }
    
    func typeConvertersToModel(propertyName:String) -> ((_ propertyValue:Any) -> Any?)? {
        switch propertyName {
            case User.accountTypeKey:
                return {(x:Any) -> Any? in
                    return AccountType(rawValue: x as! String)
                }
            case User.userTypeKey:
                return {(x:Any) -> Any? in
                    return UserType(rawValue: x as! String)
                }
            case User.sharingPermissionKey:
                return {(x:Any) -> Any? in
                    return SharingPermission(rawValue: x as! String)
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
            "username VARCHAR(\(usernameMaxLength)) NOT NULL, " +
            
            "userType VARCHAR(\(UserType.maxStringLength())) NOT NULL, " +
    
            // If non-NULL, references a user in the User table.
            "owningUserId BIGINT, " +
            
            "sharingPermission VARCHAR(\(SharingPermission.maxStringLength())), " +
        
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
        if user.username == nil || user.accountType == nil || user.credsId == nil || user.userType == nil {
            Log.error(message: "One of the model values was nil!")
            return nil
        }
        
        // Validate the JSON before we insert it. Can't really do it in the setter for creds because it's
        guard let _ = try? Creds.toCreds(accountType: user.accountType, fromJSON: user.creds, user: .user(user), delegate:nil) else {
            Log.error(message: "Invalid creds JSON: \(user.creds)")
            return nil
        }
        
        switch user.userType! {
        case .sharing:
            guard user.owningUserId != nil && user.sharingPermission != nil else {
                Log.error(message: "Sharing user, but there was no owningUserId or sharingPermission")
                return nil
            }
            
        case .owning:
            guard user.owningUserId == nil && user.sharingPermission == nil else {
                Log.error(message: "Owning user, and there was an owningUserId or sharingPermission")
                return nil
            }
        }
        
        let (owningUserIdFieldValue, owningUserIdFieldName) = getInsertFieldValueAndName(fieldValue: user.owningUserId, fieldName: "owningUserId", fieldIsString: false)
        let (sharingPermissionFieldValue, sharingPermissionFieldName) = getInsertFieldValueAndName(fieldValue: user.sharingPermission, fieldName: User.sharingPermissionKey)
        
        let query = "INSERT INTO \(tableName) (username, accountType, userType, credsId, creds \(owningUserIdFieldName) \(sharingPermissionFieldName)) VALUES('\(user.username!)', '\(user.accountType!)', '\(user.userType.rawValue)', \(user.credsId!), '\(user.creds!)' \(owningUserIdFieldValue) \(sharingPermissionFieldValue));"
        
        if db.connection.query(statement: query) {
            return db.connection.lastInsertId()
        }
        else {
            let error = db.error
            Log.error(message: "Could not insert into \(tableName): \(error)")
            return nil
        }
    }
    
    func updateCreds(creds newCreds:Creds, forUser updateCredsUser:CredsUser) -> Bool {
        var credsJSONString:String
        var userId:UserId
        
        switch updateCredsUser {
        case .user(let user):
            // First need to merge creds-- otherwise, we might override part of the creds with our update.
            // This looks like it is leaving the `user` object with changed values, but it's actually not (.credsObject generates a new `Creds` object each time it's called).
            let oldCreds = user.credsObject!
            oldCreds.merge(withNewerCreds: newCreds)
            credsJSONString = oldCreds.toJSON()!
            userId = user.userId
            
        case .userId(let id):
            credsJSONString = newCreds.toJSON()!
            userId = id
        }
        
        let query = "UPDATE \(tableName) SET creds = '\(credsJSONString)' WHERE " +
            lookupConstraint(key: .userId(userId))
        
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
