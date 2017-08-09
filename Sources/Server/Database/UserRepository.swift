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
import SyncServerShared

class User : NSObject, Model {
    static let userIdKey = "userId"
    var userId: UserId!
    
    static let usernameKey = "username"
    var username: String!
    
    // A given user on the system can only have a single UserType role, i.e., either an owning user or a sharing user.
    static let userTypeKey = "userType"
    var userType:UserType!
    
    // Only when the current user is a sharing user, this gives the userId that is the owner of the data.
    static let owningUserIdKey = "owningUserId"
    var owningUserId:UserId?

    // Only when the current user is a sharing user, this gives the permission that the sharing user has to the owning users data.
    static let sharingPermissionKey = "sharingPermission"
    var sharingPermission:SharingPermission?
    
    static let accountTypeKey = "accountType"
    var accountType: AccountType!

    // Account type specific id. E.g., for Google, this is the "sub".
    static let credsIdKey = "credsId"
    var credsId:String!
    
    static let credsKey = "creds"
    var creds:String! // Stored as JSON
    
    subscript(key:String) -> Any? {
        set {
            switch key {
            case User.userIdKey:
                userId = newValue as! UserId?

            case User.usernameKey:
                username = newValue as! String?
                
            case User.userTypeKey:
                userType = newValue as! UserType?
                
            case User.owningUserIdKey:
                owningUserId = newValue as! UserId?
                
            case User.sharingPermissionKey:
                sharingPermission = newValue as! SharingPermission?
                
            case User.accountTypeKey:
                accountType = newValue as! AccountType?
                
            case User.credsIdKey:
                credsId = newValue as! String?
            
            case User.credsKey:
                creds = newValue as! String?
                
            default:
                assert(false)
            }
        }
        
        get {
            return getValue(forKey: key)
        }
    }
    
    // Converts from the current creds JSON and accountType. Returns a new `Creds` object with each call.
    var credsObject:Account? {
        do {
            let credsObj = try AccountManager.session.accountFromJSON(creds, accountType: accountType, user: .user(self), delegate: nil)
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
    
    var effectiveOwningUserId:UserId {
        if userType == .sharing {
            return owningUserId!
        }
        else {
            return userId
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
    
    func upcreate() -> Database.TableUpcreateResult {
        let createColumns =
            "(userId BIGINT NOT NULL AUTO_INCREMENT, " +
            "username VARCHAR(\(usernameMaxLength)) NOT NULL, " +
            
            "userType VARCHAR(\(UserType.maxStringLength())) NOT NULL, " +
    
            // If non-NULL, references a user in the User table.
            // TODO: *2* Make this a foreign key reference to this same table.
            "owningUserId BIGINT, " +
            
            "sharingPermission VARCHAR(\(SharingPermission.maxStringLength())), " +
        
            "accountType VARCHAR(\(accountTypeMaxLength)) NOT NULL, " +
            
            // An id specific to the particular type of credentials, e.g., Google.
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
        
        // Validate the JSON before we insert it.
        guard let _ = try? AccountManager.session.accountFromJSON(user.creds, accountType: user.accountType, user: .user(user), delegate: nil) else {
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
    
    func updateCreds(creds newCreds:Account, forUser updateCredsUser:AccountCreationUser) -> Bool {
        var credsJSONString:String
        var userId:UserId
        
        switch updateCredsUser {
        case .user(let user):
            // First need to merge creds-- otherwise, we might override part of the creds with our update.
            // This looks like it is leaving the `user` object with changed values, but it's actually not (.credsObject generates a new `Creds` object each time it's called).
            let oldCreds = user.credsObject!
            oldCreds.merge(withNewer: newCreds)
            credsJSONString = oldCreds.toJSON()!
            userId = user.userId
            
        case .userId(let id, _):
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
