//
//  SharingGroupUserRepository.swift
//  Server
//
//  Created by Christopher G Prince on 6/24/18.
//

// What users are in specific sharing groups?

import Foundation
import LoggerAPI
import SyncServerShared

typealias SharingGroupUserId = Int64

class SharingGroupUser : NSObject, Model {
    static let sharingGroupUserIdKey = "sharingGroupUserId"
    var sharingGroupUserId: SharingGroupUserId!
    
    // Each record in this table relates a sharing group...
    static let sharingGroupIdKey = "sharingGroupId"
    var sharingGroupId: SharingGroupId!
    
    // ... to a user.
    static let userIdKey = "userId"
    var userId: UserId!
    
    // Only when the current user (identified by the userId) is a sharing user, this gives the userId that is the owner of the data for this sharing group.
    static let owningUserIdKey = "owningUserId"
    var owningUserId:UserId?

    // The permissions that the user has in regards to the sharing group. The user can read (anyone's data), can upload (to their own or others storage), and invite others to join the group.
    static let permissionKey = "permission"
    var permission:Permission?

    subscript(key:String) -> Any? {
        set {
            switch key {
            case SharingGroupUser.sharingGroupUserIdKey:
                sharingGroupUserId = newValue as! SharingGroupUserId?
            
            case SharingGroupUser.userIdKey:
                userId = newValue as! UserId?
                
            case SharingGroupUser.sharingGroupIdKey:
                sharingGroupId = newValue as! SharingGroupId?
                
            case SharingGroupUser.permissionKey:
                permission = newValue as! Permission?
                
            case SharingGroupUser.owningUserIdKey:
                owningUserId = newValue as! UserId?
                
            default:
                Log.error("Did not find key: \(key)")
                assert(false)
            }
        }
        
        get {
            return getValue(forKey: key)
        }
    }
    
    func typeConvertersToModel(propertyName:String) -> ((_ propertyValue:Any) -> Any?)? {
        switch propertyName {
            case SharingGroupUser.permissionKey:
                return {(x:Any) -> Any? in
                    return Permission(rawValue: x as! String)
                }
            default:
                return nil
        }
    }
    
    override init() {
        super.init()
    }
}

class SharingGroupUserRepository : Repository, RepositoryLookup {
    private(set) var db:Database!
    
    required init(_ db:Database) {
        self.db = db
    }
    
    var tableName:String {
        return SharingGroupUserRepository.tableName
    }
    
    static var tableName:String {
        return "SharingGroupUser"
    }
    
    func upcreate() -> Database.TableUpcreateResult {
        let createColumns =
            "(sharingGroupUserId BIGINT NOT NULL AUTO_INCREMENT, " +
        
            "sharingGroupId BIGINT NOT NULL, " +
            
            "userId BIGINT NOT NULL, " +
            
            // NULL for only owning users; sharing users must have non-NULL value.
            "owningUserId BIGINT, " +
            
            "permission VARCHAR(\(Permission.maxStringLength())), " +

            "FOREIGN KEY (owningUserId) REFERENCES \(UserRepository.tableName)(\(User.userIdKey)), " +
            "FOREIGN KEY (userId) REFERENCES \(UserRepository.tableName)(\(User.userIdKey)), " +
            "FOREIGN KEY (sharingGroupId) REFERENCES \(SharingGroupRepository.tableName)(\(SharingGroup.sharingGroupIdKey)), " +

            "UNIQUE (sharingGroupId, userId), " +
            "UNIQUE (sharingGroupUserId))"
        
        let result = db.createTableIfNeeded(tableName: "\(tableName)", columnCreateQuery: createColumns)
        return result
    }
    
    enum LookupKey : CustomStringConvertible {
        case sharingGroupUserId(SharingGroupUserId)
        case primaryKeys(sharingGroupId: SharingGroupId, userId: UserId)
        case userId(UserId)
        case sharingGroupId(SharingGroupId)
        case owningUserId(UserId)
        case owningUserAndSharingGroup(owningUserId: UserId, SharingGroupId)
        
        var description : String {
            switch self {
            case .sharingGroupUserId(let sharingGroupUserId):
                return "sharingGroupUserId(\(sharingGroupUserId))"
            case .primaryKeys(sharingGroupId: let sharingGroupId, userId: let userId):
                return "primaryKeys(\(sharingGroupId), \(userId))"
            case .userId(let userId):
                return "userId(\(userId))"
            case .sharingGroupId(let sharingGroupId):
                return "sharingGroupId(\(sharingGroupId))"
            case .owningUserId(let owningUserId):
                return "owningUserId(\(owningUserId))"
            case .owningUserAndSharingGroup(owningUserId: let owningUserId, let sharingGroupId):
                return "owningUserId(\(owningUserId), \(sharingGroupId)"
            }
        }
    }
    
    func lookupConstraint(key:LookupKey) -> String {
        switch key {
        case .sharingGroupUserId(let sharingGroupUserId):
            return "sharingGroupUserId = \(sharingGroupUserId)"
        case .primaryKeys(sharingGroupId: let sharingGroupId, userId: let userId):
            return "sharingGroupId = \(sharingGroupId) AND userId = \(userId)"
        case .userId(let userId):
            return "userId = \(userId)"
        case .sharingGroupId(let sharingGroupId):
            return "sharingGroupId = \(sharingGroupId)"
        case .owningUserId(let owningUserId):
            return "owningUserId = \(owningUserId)"
        case .owningUserAndSharingGroup(owningUserId: let owningUserId, let sharingGroupId):
            return "owningUserId = \(owningUserId) AND sharingGroupId = \(sharingGroupId)"
        }
    }
    
    enum AddResult {
        case success(SharingGroupUserId)
        case error(String)
    }
    
    func add(sharingGroupId: SharingGroupId, userId: UserId, permission: Permission, owningUserId: UserId?) -> AddResult {
        let owningUserIdValue = owningUserId == nil ? "NULL" : "\(owningUserId!)"
        let query = "INSERT INTO \(tableName) (sharingGroupId, userId, permission, owningUserId) VALUES(\(sharingGroupId), \(userId), '\(permission.rawValue)', \(owningUserIdValue));"
        
        if db.connection.query(statement: query) {
            Log.info("Sucessfully created sharing user group")
            return .success(db.connection.lastInsertId())
        }
        else {
            let error = db.error
            Log.error("Could not insert into \(tableName): \(error)")
            return .error(error)
        }
    }
    
    enum SharingGroupUserResult {
        case sharingGroupUsers([SyncServerShared.SharingGroupUser])
        case error(String)
    }
    
    func sharingGroupUsers(forSharingGroupId sharingGroupId: SharingGroupId) -> SharingGroupUserResult {
        let query = "select \(UserRepository.tableName).\(User.usernameKey),  \(UserRepository.tableName).\(User.userIdKey) from \(tableName), \(UserRepository.tableName) where \(tableName).userId = \(UserRepository.tableName).userId and \(tableName).sharingGroupId = \(sharingGroupId)"
        return sharingGroupUsers(forSelectQuery: query)
    }
    
    private func sharingGroupUsers(forSelectQuery selectQuery: String) -> SharingGroupUserResult {
        let select = Select(db:db, query: selectQuery, modelInit: User.init, ignoreErrors:false)
        
        var result:[SyncServerShared.SharingGroupUser] = []
        
        select.forEachRow { rowModel in
            let rowModel = rowModel as! User

            let sharingGroupUser = SyncServerShared.SharingGroupUser()!
            sharingGroupUser.name = rowModel.username
            sharingGroupUser.userId = rowModel.userId
            
            result.append(sharingGroupUser)
        }
        
        if select.forEachRowStatus == nil {
            return .sharingGroupUsers(result)
        }
        else {
            return .error("\(select.forEachRowStatus!)")
        }
    }
    
    // To deal with deleting a user account-- any other users that have its user id as their owningUserId must have that owningUserId set to NULL. Don't just remove the invited/sharing user from SharingGroupUsers-- why not let them still download from the sharing group?
    func resetOwningUserIds(key: LookupKey) -> Bool {
        let query = "UPDATE \(tableName) SET owningUserId = NULL WHERE " + lookupConstraint(key: key)
        
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

