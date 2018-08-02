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
    
    static let sharingGroupNameKey = "sharingGroupName"
    var sharingGroupName: String!
    
    static let deletedKey = "deleted"
    var deleted:Bool!

    subscript(key:String) -> Any? {
        set {
            switch key {
            case SharingGroup.sharingGroupIdKey:
                sharingGroupId = newValue as! SharingGroupId?

            case SharingGroup.sharingGroupNameKey:
                sharingGroupName = newValue as! String?
            
            case SharingGroup.deletedKey:
                deleted = newValue as! Bool?
                
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

            // A name for the sharing group-- assigned by the client app.
            "sharingGroupName VARCHAR(\(Database.maxSharingGroupNameLength)), " +
            
            // true iff sharing group has been deleted. Like file references in the FileIndex, I'm never going to actually delete sharing groups.
            "deleted BOOL NOT NULL, " +
            
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
    
    func add(sharingGroupName: String? = nil) -> AddResult {
        let insert = Database.Insert(repo: self)
        
        // Deal with table that has only an autoincrement column: https://stackoverflow.com/questions/5962026/mysql-inserting-in-table-with-only-an-auto-incrementing-column (This is only really necessary if no sharing group name is given.)
        insert.add(fieldName: SharingGroup.sharingGroupIdKey, value: .null)
        insert.add(fieldName: SharingGroup.deletedKey, value: .bool(false))

        if let sharingGroupName = sharingGroupName {
            insert.add(fieldName: SharingGroup.sharingGroupNameKey, value: .string(sharingGroupName))
        }
        
        do {
            let id = try insert.run()
            Log.info("Sucessfully created sharing group")
            return .success(id)
        }
        catch (let error) {
            Log.error("Could not insert into \(tableName): \(error)")
            return .error("\(error)")
        }
    }

    func sharingGroups(forUserId userId: UserId) -> [SharingGroup]? {
        let sharingGroupUserTableName = SharingGroupUserRepository.tableName
        let query = "select \(tableName).sharingGroupId, \(tableName).sharingGroupName from \(tableName),\(sharingGroupUserTableName) where \(sharingGroupUserTableName).userId = \(userId) and \(sharingGroupUserTableName).sharingGroupId = \(tableName).sharingGroupId"
        return sharingGroups(forSelectQuery: query)
    }
    
    private func sharingGroups(forSelectQuery selectQuery: String) -> [SharingGroup]? {
        let select = Select(db:db, query: selectQuery, modelInit: SharingGroup.init, ignoreErrors:false)
        
        var result = [SharingGroup]()
        
        select.forEachRow { rowModel in
            let rowModel = rowModel as! SharingGroup
            result.append(rowModel)
        }
        
        if select.forEachRowStatus == nil {
            return result
        }
        else {
            return nil
        }
    }
    
    enum MarkDeletionCriteria {
        case sharingGroupId(SharingGroupId)
        
        func toString() -> String {
            switch self {
            case .sharingGroupId(let sharingGroupId):
                return "\(SharingGroup.sharingGroupIdKey)=\(sharingGroupId)"
            }
        }
    }
    
    func markAsDeleted(forCriteria criteria: MarkDeletionCriteria) -> Int64? {
        let query = "UPDATE \(tableName) SET \(SharingGroup.deletedKey)=1 WHERE " + criteria.toString()
        if db.connection.query(statement: query) {
            return db.connection.numberAffectedRows()
        }
        else {
            let error = db.error
            Log.error("Could not mark files as deleted in \(tableName): \(error)")
            return nil
        }
    }
}

