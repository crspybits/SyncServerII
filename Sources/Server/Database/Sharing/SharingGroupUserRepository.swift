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

    subscript(key:String) -> Any? {
        set {
            switch key {
            case SharingGroupUser.sharingGroupUserIdKey:
                sharingGroupUserId = newValue as! SharingGroupUserId?
            
            case SharingGroupUser.userIdKey:
                userId = newValue as! UserId?
                
            case SharingGroupUser.sharingGroupIdKey:
                sharingGroupId = newValue as! SharingGroupId?
                
            default:
                Log.error("Did not find key: \(key)")
                assert(false)
            }
        }
        
        get {
            return getValue(forKey: key)
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
        
        var description : String {
            switch self {
            case .sharingGroupUserId(let sharingGroupUserId):
                return "sharingGroupUserId(\(sharingGroupUserId))"
            case .primaryKeys(sharingGroupId: let sharingGroupId, userId: let userId):
                return "primaryKeys(\(sharingGroupId), \(userId))"
            case .userId(let userId):
                return "userId(\(userId))"
            }
        }
    }
    
    func lookupConstraint(key:LookupKey) -> String {
        switch key {
        case .sharingGroupUserId(let sharingGroupUserId):
            return "sharingGroupUserId = \(sharingGroupUserId)"
        case .primaryKeys(sharingGroupId: let sharingGroupId, userId: let userId):
            return "sharingGroupId = \(sharingGroupId) and userId = \(userId)"
        case .userId(let userId):
            return "userId = \(userId)"
        }
    }
    
    enum AddResult {
        case success(SharingGroupUserId)
        case error(String)
    }
    
    func add(sharingGroupId: SharingGroupId, userId: UserId) -> AddResult {
        let query = "INSERT INTO \(tableName) (sharingGroupId, userId) VALUES(\(sharingGroupId), \(userId));"
        
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
    
    func sharingGroups(forUserId userId: UserId) -> [SharingGroupUser]? {
        let query = "select * from \(tableName) where userId = \(userId)"
        return sharingGroups(forSelectQuery: query)
    }
    
    private func sharingGroups(forSelectQuery selectQuery: String) -> [SharingGroupUser]? {
        let select = Select(db:db, query: selectQuery, modelInit: SharingGroupUser.init, ignoreErrors:false)
        
        var result = [SharingGroupUser]()
        
        select.forEachRow { rowModel in
            let rowModel = rowModel as! SharingGroupUser
            result.append(rowModel)
        }
        
        if select.forEachRowStatus == nil {
            return result
        }
        else {
            return nil
        }
    }
}

