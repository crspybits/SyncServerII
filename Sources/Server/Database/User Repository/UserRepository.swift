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
import ServerShared
import LoggerAPI
import ServerAccount

class User : NSObject, Model, UserData {
    required override init() {
        super.init()
    }

    static let userIdKey = "userId"
    var userId: UserId!
    
    static let usernameKey = "username"
    var username: String!
    
    static let accountTypeKey = "accountType"
    var accountType: AccountScheme.AccountName!

    // Account type specific id. E.g., for Google, this is the "sub".
    static let credsIdKey = "credsId"
    var credsId:String!
    
    static let credsKey = "creds"
    var creds:String! // Stored as JSON
    
    // Only used by some owning user accounts (e.g., Google Drive).
    static let cloudFolderNameKey = "cloudFolderName"
    var cloudFolderName: String?
    
    static let pushNotificationTopicKey = "pushNotificationTopic"
    var pushNotificationTopic: String?
    
    subscript(key:String) -> Any? {
        set {
            switch key {
            case User.userIdKey:
                userId = newValue as! UserId?

            case User.usernameKey:
                username = newValue as! String?
                
            case User.accountTypeKey:
                accountType = newValue as! AccountScheme.AccountName?
                
            case User.credsIdKey:
                credsId = newValue as! String?
            
            case User.credsKey:
                creds = newValue as! String?
            
            case User.cloudFolderNameKey:
                cloudFolderName = newValue as! String?
                
            case User.pushNotificationTopicKey:
                pushNotificationTopic = newValue as! String?
                
            default:
                assert(false)
            }
        }
        
        get {
            return getValue(forKey: key)
        }
    }
}

class UserRepository : Repository, RepositoryLookup {
    private(set) var db:Database!
    
    // Set this after you create the UserRepository
    var accountManager: AccountManager!
    
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
            
            // Just a displayable/UI textual name for the user. Not a login name or email address.
            "username VARCHAR(\(usernameMaxLength)) NOT NULL, " +
        
            "accountType VARCHAR(\(accountTypeMaxLength)) NOT NULL, " +
            
            // An id specific to the particular type of credentials, e.g., Google.
            "credsId VARCHAR(\(credsIdMaxLength)) NOT NULL, " +
        
            // Stored as JSON. Credential specifics for the particular accountType.
            "creds TEXT NOT NULL, " +
            
            // Can be null because only some cloud storage accounts use this and only owning user accounts use this.
            "cloudFolderName VARCHAR(\(AddUserRequest.maxCloudFolderNameLength)), " +
            
            // A push notification topic for AWS SNS is a group containing endpoint ARN's for all the users registered devices. This will be NULL if a user has no registered devices.
            "pushNotificationTopic TEXT, " +
            
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
        case accountTypeInfo(accountType:AccountScheme.AccountName, credsId:String)
        
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
    // 6/12/19; Added `validateJSON`-- this is only for testing and normally should be left with the true default value.
    func add(user:User, accountManager: AccountManager, accountDelegate: AccountDelegate?, validateJSON: Bool = true) -> Int64? {
        if user.username == nil || user.accountType == nil || user.credsId == nil {
            Log.error("One of the model values was nil!")
            return nil
        }
        
        if validateJSON {
            // Validate the JSON before we insert it.
            guard let _ = try? accountManager.accountFromJSON(user.creds, accountName: user.accountType, user: .user(user), accountDelegate: accountDelegate) else {
                Log.error("Invalid creds JSON: \(String(describing: user.creds)) for accountType: \(String(describing: user.accountType))")
                return nil
            }
        }

        let (cloudFolderNameFieldValue, cloudFolderNameFieldName) = getInsertFieldValueAndName(fieldValue: user.cloudFolderName, fieldName: User.cloudFolderNameKey)
        
        let query = "INSERT INTO \(tableName) (username, accountType, credsId, creds \(cloudFolderNameFieldName)) VALUES('\(user.username!)', '\(user.accountType!)', '\(user.credsId!)', '\(user.creds!)' \(cloudFolderNameFieldValue));"
        
        if db.query(statement: query) {
            return db.lastInsertId()
        }
        else {
            let error = db.error
            Log.error("Could not insert into \(tableName): \(error)")
            Log.error("query: \(query)")
            return nil
        }
    }
    
    func updateCreds(creds newCreds:Account, forUser updateCredsUser:AccountCreationUser, accountManager: AccountManager) -> Bool {
        var credsJSONString:String
        var userId:UserId
        
        switch updateCredsUser {
        case .user(let oldCredsUser):
            // First need to merge creds-- otherwise, we might override part of the creds with our update.
            
            // the `accountDelegate` is passed as nil because the `updateCreds` method is what is used to implement the saveToDatabase call and it's cyclic to pass the delegate in this case.
            guard let oldCreds = try? accountManager.accountFromJSON(oldCredsUser.creds, accountName: oldCredsUser.accountType, user: .user(oldCredsUser), accountDelegate: nil) else {
                return false
            }
            
            oldCreds.merge(withNewer: newCreds)
            credsJSONString = oldCreds.toJSON()!
            userId = oldCredsUser.userId
            
        case .userId(let id):
            credsJSONString = newCreds.toJSON()!
            userId = id
        }
        
        Log.debug("credsJSONString: \(credsJSONString)")
        
        let update = Database.PreparedStatement(repo: self, type: .update)
        update.add(fieldName: User.credsKey, value: .string(credsJSONString))
        update.where(fieldName: User.userIdKey, value: .int64(userId))
        
        do {
            try update.run()
        }
        catch (let error) {
            Log.error("Failed updating User: \(error)")
            return false
        }
        
        return true
    }
    
    // For a sharing user, will have one element per sharing group the user is a member of. These are the "owners" or "parents" of the sharing groups the sharing user is in. Returns an empty list if the user isn't a sharing user.
    func getOwningSharingGroupUsers(forSharingUserId userId: UserId) -> [User]? {
        let sharingGroupUserTableName = SharingGroupUserRepository.tableName
        
        let selectQuery = "select DISTINCT \(tableName).* FROM \(sharingGroupUserTableName), \(tableName) WHERE \(sharingGroupUserTableName).userId = \(userId) and \(sharingGroupUserTableName).owningUserId = \(tableName).userId"

        guard let select = Select(db:db, query: selectQuery, modelInit: User.init, ignoreErrors:false) else {
            return nil
        }
        
        var result:[User] = []
        
        select.forEachRow { rowModel in
            let rowModel = rowModel as! User
            result.append(rowModel)
        }
        
        if select.forEachRowStatus == nil {
            return result
        }
        else {
            return nil
        }
    }
    
    func updatePushNotificationTopic(forUserId userId: UserId, topic: String?) -> Bool {
        let topicText = topic ?? "NULL"
        let query = "UPDATE \(tableName) SET pushNotificationTopic = '\(topicText)' WHERE " +
            lookupConstraint(key: .userId(userId))
        
        if db.query(statement: query) {
            let numberUpdates = db.numberAffectedRows()
            // 7/6/18; I'm allowing 0 updates -- in case the update doesn't change the row.
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
}
