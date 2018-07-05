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

    subscript(key:String) -> Any? {
        set {
            switch key {
            case SharingGroup.sharingGroupIdKey:
                sharingGroupId = newValue as! SharingGroupId?
                
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

class SharingGroupRepository: Repository, RepositoryLookup {
    private(set) var db:Database!
    
    required init(_ db:Database) {
        self.db = db
    }
    
    var tableName:String {
        return SharingGroupRepository.tableName
    }
    
    static var tableName:String {
        return "SharingGroup"
    }
    
    func upcreate() -> Database.TableUpcreateResult {
        let createColumns =
            "(sharingGroupId BIGINT NOT NULL AUTO_INCREMENT, " +
        
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
    
    // Note that if there are references in the FileIndex to sharingGroupId's, I'm never going to delete the reference in the SharingGroup table. This is because we never really delete files-- we just mark them as deleted.
    func add() -> AddResult {
        // Deal with table that has only an autoincrement column: https://stackoverflow.com/questions/5962026/mysql-inserting-in-table-with-only-an-auto-incrementing-column
        let query = "INSERT INTO \(tableName) (sharingGroupId) values (null)"
        
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
