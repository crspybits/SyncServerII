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
                
            default:
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

class SharingGroupUserRepository : Repository {
    private(set) var db:Database!
    
    init(_ db:Database) {
        self.db = db
    }
    
    var tableName:String {
        return SharingGroupUserRepository.tableName
    }
    
    static var tableName:String {
        return "SharingGroupUser"
    }
    
    // TODO: How do you do deletions of rows with foreign keys?
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
        
        var description : String {
            switch self {
            case .sharingGroupUserId(let sharingGroupUserId):
                return "sharingGroupUserId(\(sharingGroupUserId))"
            case .primaryKeys(sharingGroupId: let sharingGroupId, userId: let userId):
                return "primaryKeys(\(sharingGroupId), \(userId))"
            }
        }
    }
    
    func lookupConstraint(key:LookupKey) -> String {
        switch key {
        case .sharingGroupUserId(let sharingGroupUserId):
            return "sharingGroupUserId = \(sharingGroupUserId)"
        case .primaryKeys(sharingGroupId: let sharingGroupId, userId: let userId):
            return "sharingGroupId = \(sharingGroupId) and userId = \(userId)"
        }
    }
    
    enum AddResult {
        case success(SharingGroupUserId)
        case error(String)
    }
    
    func add(sharingGroupId: SharingGroupId, userId: UserId) -> AddResult {
        let query = "INSERT INTO \(tableName) (sharingGroupId, userId) VALUES(\(sharingGroupId), \(userId));"
        
        if db.connection.query(statement: query) {
            Log.info("Sucessfully created sharing group")
            return .success(db.connection.lastInsertId())
        }
        else {
            let error = db.error
            Log.error("Could not insert into \(tableName): \(error)")
            return .error(error)
        }
    }
}

