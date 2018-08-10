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
            default:
                return nil
        }
    }
    
    // This can be nil in the case where (a) the user is a sharing user, and (b) it original inviting user has been deleted from the system.
    var effectiveOwningUserId:UserId? {
        if accountType.userType == .sharing {
            return owningUserId
        }
        else {
            return userId
        }
    }
}

class UserRepository : Repository, RepositoryLookup {
    private(set) var db:Database!

    required init(_ db:Database) {
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
                
            // If non-NULL, references a user in the User table.
            // TODO: *2* Make this a foreign key reference to this same table.
            "owningUserId BIGINT, " +
        
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
        let (cloudFolderNameFieldValue, cloudFolderNameFieldName) = getInsertFieldValueAndName(fieldValue: user.cloudFolderName, fieldName: User.cloudFolderNameKey)
        
        let query = "INSERT INTO \(tableName) (username, accountType, credsId, creds \(owningUserIdFieldName)\(cloudFolderNameFieldName)) VALUES('\(user.username!)', '\(user.accountType!)', '\(user.credsId!)', '\(user.creds!)' \(owningUserIdFieldValue) \(cloudFolderNameFieldValue));"
        
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
            // 7/6/18; I'm allowing 0 updates because in some cases, e.g., Dropbox, there will be no change in the row.
            guard numberUpdates <= 1 else {
                Log.error("Expected <= 1 updated, but had \(numberUpdates)")
                return false
            }

            return true
        }
        else {
            let error = db.error
            Log.error("Could not update row for \(tableName): \(error)")
            return false
        }
    }
    
    // To deal with deleting the userId account-- any other users that have its user id as their owningUserId must have that owningUserId set to NULL.
    func resetOwningUserIds(forUserId userId: UserId) -> Bool {
        let query = "UPDATE \(tableName) SET owningUserId = NULL WHERE owningUserId = \(userId)"
        
        if db.connection.query(statement: query) {
            let numberUpdates = db.connection.numberAffectedRows()
            Log.info("\(numberUpdates) users had their owningUserId set to NULL.")
            return true
        }
        else {
            let error = db.error
            Log.error("Could not update row(s) for \(tableName): \(error)")
            return false
        }
    }
}
