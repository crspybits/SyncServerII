//
//  SharingGroupRepository.swift
//  Server
//
//  Created by Christopher G Prince on 6/23/18.
//

// A sharing group is a group of users who are sharing a collection of files.

import Foundation
import LoggerAPI
import SyncServerShared

class SharingGroup : NSObject, Model {
    static let sharingGroupIdKey = "sharingGroupId"
    var sharingGroupId: SharingGroupId!
    
    // The userId of the "root" user for the group-- the one who started the sharing group.
    static let creatingUserIdKey = "userId"
    var creatingUserId: UserId!

    subscript(key:String) -> Any? {
        set {
            switch key {
            case SharingGroup.sharingGroupIdKey:
                sharingGroupId = newValue as! SharingGroupId?
            
            case SharingGroup.creatingUserIdKey:
                creatingUserId = newValue as! UserId?
                
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

class SharingGroupRepository : Repository {
    private(set) var db:Database!
    
    init(_ db:Database) {
        self.db = db
    }
    
    var tableName:String {
        return SharingGroupRepository.tableName
    }
    
    static var tableName:String {
        return "SharingGroup"
    }
    
    // TODO: How do you do deletions of rows with foreign keys?
    func upcreate() -> Database.TableUpcreateResult {
        let createColumns =
            "(sharingGroupId BIGINT NOT NULL AUTO_INCREMENT, " +
        
            "creatingUserId BIGINT NOT NULL, " +

            "FOREIGN KEY (creatingUserId) REFERENCES \(UserRepository.tableName)(\(User.userIdKey)), " +
            "UNIQUE (sharingGroupId))"
        
        let result = db.createTableIfNeeded(tableName: "\(tableName)", columnCreateQuery: createColumns)
        return result
    }
    
    enum LookupKey : CustomStringConvertible {
        case sharingGroupId(SharingGroupId)
        
        var description : String {
            switch self {
            case .sharingGroupId(let sharingGroupId):
                return "sharingGroupId(\(sharingGroupId))"
            }
        }
    }
    
    func lookupConstraint(key:LookupKey) -> String {
        switch key {
        case .sharingGroupId(let sharingGroupId):
            return "sharingGroupId = \(sharingGroupId)"
        }
    }
    
    enum AddResult {
        case success(SharingGroupId)
        case error(String)
    }
    
    func add(creatingUserId:UserId) -> AddResult {
        let query = "INSERT INTO \(tableName) (creatingUserId) VALUES(\(creatingUserId));"
        
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

