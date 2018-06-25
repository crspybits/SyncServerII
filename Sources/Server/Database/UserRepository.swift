//
//  UserRepository.swift
//  Server
//
//  Created by Christopher Prince on 11/26/16.
//
//

import Foundation
import Credentials
import CredentialsGoogle
import SyncServerShared
import LoggerAPI

class User : NSObject, Model {
    static let userIdKey = "userId"
    var userId: UserId!
    
    static let usernameKey = "username"
    var username: String!
    
    // Only when the current user is a sharing user, this gives the userId that is the owner of the data.
    static let owningUserIdKey = "owningUserId"
    var owningUserId:UserId?

    // The permissions that the user has in regards to the sharing group of users. The user can read (anyone's data), can upload (to their own or others storage), and invite others to join the group.
    static let permissionKey = "permission"
    var permission:Permission?
    
    static let accountTypeKey = "accountType"
    var accountType: AccountType!

    // Account type specific id. E.g., for Google, this is the "sub".
    static let credsIdKey = "credsId"
    var credsId:String!
    
    static let credsKey = "creds"
    var creds:String! // Stored as JSON
    
    // Only used by some owning user accounts (e.g., Google Drive).
    static let cloudFolderNameKey = "cloudFolderName"
    var cloudFolderName: String?
    
    subscript(key:String) -> Any? {
        set {
            switch key {
            case User.userIdKey:
                userId = newValue as! UserId?

            case User.usernameKey:
                username = newValue as! String?
                
            case User.owningUserIdKey:
                owningUserId = newValue as! UserId?
                
            case User.permissionKey:
                permission = newValue as! Permission?
                
            case User.accountTypeKey:
                accountType = newValue as! AccountType?
                
            case User.credsIdKey:
                credsId = newValue as! String?
            
            case User.credsKey:
                creds = newValue as! String?
            
            case User.cloudFolderNameKey:
                cloudFolderName = newValue as! String?
                
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
            Log.error("\(error)")
            return nil
        }
    }
    
    func typeConvertersToModel(propertyName:String) -> ((_ propertyValue:Any) -> Any?)? {
        switch propertyName {
            case User.accountTypeKey:
                return {(x:Any) -> Any? in
                    return AccountType(rawValue: x as! String)
                }
            case User.permissionKey:
                return {(x:Any) -> Any? in
                    return Permission(rawValue: x as! String)
                }
            default:
                return nil
        }
    }
    
    var effectiveOwningUserId:UserId {
        if accountType.userType == .sharing {
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
        return UserRepository.tableName
    }
    
    static var tableName:String {
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
            
            "permission VARCHAR(\(Permission.maxStringLength())), " +
        
            "accountType VARCHAR(\(accountTypeMaxLength)) NOT NULL, " +
            
            // An id specific to the particular type of credentials, e.g., Google.
            "credsId VARCHAR(\(credsIdMaxLength)) NOT NULL, " +
        
            // Stored as JSON
            "creds TEXT NOT NULL, " +
            
            // Can be null because only some cloud storage accounts use this and only owning user accounts use this.
            "cloudFolderName VARCHAR(\(AddUserRequest.maxCloudFolderNameLength)), " +
            
            // I'm not going to require that the username be unique. The userId is unique.
            
            "UNIQUE (accountType, credsId), " +
            "UNIQUE (userId))"
        
        let result = db.createTableIfNeeded(tableName: "\(tableName)", columnCreateQuery: createColumns)
        
        switch result {
        case .success(.alreadyPresent):
            // Table was already there. Do we need to update it?
            
            // 2/25/18; Evolution 2: Add cloudFolderName column
            if db.columnExists(User.cloudFolderNameKey, in: tableName) == false {
                if !db.addColumn("\(User.cloudFolderNameKey) VARCHAR(\(AddUserRequest.maxCloudFolderNameLength))", to: tableName) {
                    return .failure(.columnCreation)
                }
            }
            
        default:
            break
        }
        
        return result
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
            Log.error("One of the model values was nil!")
            return nil
        }
        
        // Validate the JSON before we insert it.
        guard let _ = try? AccountManager.session.accountFromJSON(user.creds, accountType: user.accountType, user: .user(user), delegate: nil) else {
            Log.error("Invalid creds JSON: \(user.creds) for accountType: \(user.accountType)")
            return nil
        }
        
        guard user.permission != nil else {
            Log.error("All user must have permissions.")
            return nil
        }
        
        switch user.accountType.userType {
        case .sharing:
            guard user.owningUserId != nil else {
                Log.error("Sharing user, but there was no owningUserId")
                return nil
            }
            
        case .owning:
            guard user.owningUserId == nil else {
                Log.error("Owning user, and there was an owningUserId")
                return nil
            }
        }
        
        let (owningUserIdFieldValue, owningUserIdFieldName) = getInsertFieldValueAndName(fieldValue: user.owningUserId, fieldName: "owningUserId", fieldIsString: false)
        let (permissionFieldValue, permissionFieldName) = getInsertFieldValueAndName(fieldValue: user.permission, fieldName: User.permissionKey)
        let (cloudFolderNameFieldValue, cloudFolderNameFieldName) = getInsertFieldValueAndName(fieldValue: user.cloudFolderName, fieldName: User.cloudFolderNameKey)
        
        let query = "INSERT INTO \(tableName) (username, accountType, credsId, creds \(owningUserIdFieldName) \(permissionFieldName) \(cloudFolderNameFieldName)) VALUES('\(user.username!)', '\(user.accountType!)', '\(user.credsId!)', '\(user.creds!)' \(owningUserIdFieldValue) \(permissionFieldValue) \(cloudFolderNameFieldValue));"
        
        if db.connection.query(statement: query) {
            return db.connection.lastInsertId()
        }
        else {
            let error = db.error
            Log.error("Could not insert into \(tableName): \(error)")
            Log.error("query: \(query)")
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
            credsJSONString = oldCreds.toJSON(userType:user.accountType.userType)!
            userId = user.userId
            
        case .userId(let id, let userType):
            credsJSONString = newCreds.toJSON(userType: userType)!
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
                Log.error("Expected 1 update, but had \(numberUpdates)")
                return false
            }
        }
        else {
            let error = db.error
            Log.error("Could not update row for \(tableName): \(error)")
            return false
        }
    }
}
