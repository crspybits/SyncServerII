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
    
    // Not a part of this table, but a convenience for doing joins with the MasterVersion table.
    static let masterVersionKey = "masterVersion"
    var masterVersion: MasterVersionInt!

    // Similarly, not part of this table. For doing joins.
    public static let permissionKey = "permission"
    public var permission:Permission?
    
    // Also not part of this table. For doing fetches of sharing group users for the sharing group.
    public var sharingGroupUsers:[SyncServerShared.SharingGroupUser]!

    subscript(key:String) -> Any? {
        set {
            switch key {
            case SharingGroup.sharingGroupIdKey:
                sharingGroupId = newValue as! SharingGroupId?

            case SharingGroup.sharingGroupNameKey:
                sharingGroupName = newValue as! String?
            
            case SharingGroup.deletedKey:
                deleted = newValue as! Bool?

            case SharingGroup.masterVersionKey:
                masterVersion = newValue as! MasterVersionInt?
                
            case SharingGroup.permissionKey:
                permission = newValue as! Permission?
                
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
    
    func typeConvertersToModel(propertyName:String) -> ((_ propertyValue:Any) -> Any?)? {
        switch propertyName {
            case SharingGroup.deletedKey:
                return {(x:Any) -> Any? in
                    return (x as! Int8) == 1
                }
            case SharingGroupUser.permissionKey:
                return {(x:Any) -> Any? in
                    return Permission(rawValue: x as! String)
                }
            default:
                return nil
        }
    }
    
    func toClient() -> SyncServerShared.SharingGroup  {
        let clientGroup = SyncServerShared.SharingGroup()!
        clientGroup.sharingGroupId = sharingGroupId
        clientGroup.sharingGroupName = sharingGroupName
        clientGroup.deleted = deleted
        clientGroup.masterVersion = masterVersion
        clientGroup.permission = permission
        clientGroup.sharingGroupUsers = sharingGroupUsers
        return clientGroup
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
        let insert = Database.PreparedStatement(repo: self, type: .insert)
        
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

    func sharingGroups(forUserId userId: UserId, sharingGroupUserRepo: SharingGroupUserRepository) -> [SharingGroup]? {
        let masterVersionTableName = MasterVersionRepository.tableName
        let sharingGroupUserTableName = SharingGroupUserRepository.tableName
        
        let query = "select \(tableName).sharingGroupId, \(tableName).sharingGroupName, \(tableName).deleted, \(masterVersionTableName).masterVersion, \(sharingGroupUserTableName).permission FROM \(tableName),\(sharingGroupUserTableName), \(masterVersionTableName) WHERE \(sharingGroupUserTableName).userId = \(userId) AND \(sharingGroupUserTableName).sharingGroupId = \(tableName).sharingGroupId AND \(tableName).sharingGroupId = \(masterVersionTableName).sharingGroupId"
        return sharingGroups(forSelectQuery: query, sharingGroupUserRepo: sharingGroupUserRepo)
    }
    
    private func sharingGroups(forSelectQuery selectQuery: String, sharingGroupUserRepo: SharingGroupUserRepository) -> [SharingGroup]? {
        let select = Select(db:db, query: selectQuery, modelInit: SharingGroup.init, ignoreErrors:false)
        
        var result = [SharingGroup]()
        var errorGettingSgus = false
        
        select.forEachRow { rowModel in
            let sharingGroup = rowModel as! SharingGroup
            
            let sguResult = sharingGroupUserRepo.sharingGroupUsers(forSharingGroupId: sharingGroup.sharingGroupId)
            switch sguResult {
            case .sharingGroupUsers(let sgus):
                sharingGroup.sharingGroupUsers = sgus
            case .error(let error):
                Log.error(error)
                errorGettingSgus = true
                return
            }
            
            result.append(sharingGroup)
        }
        
        if !errorGettingSgus && select.forEachRowStatus == nil {
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
    
    func update(sharingGroup: SharingGroup) -> Bool {
        let update = Database.PreparedStatement(repo: self, type: .update)
        
        guard let sharingGroupId = sharingGroup.sharingGroupId,
            let sharingGroupName = sharingGroup.sharingGroupName else {
            return false
        }
        
        update.add(fieldName: SharingGroup.sharingGroupNameKey, value: .string(sharingGroupName))
        update.where(fieldName: SharingGroup.sharingGroupIdKey, value: .int64(sharingGroupId))
        
        do {
            try update.run()
        }
        catch (let error) {
            Log.error("Failed updating sharing group: \(error)")
            return false
        }
        
        return true
    }
}

