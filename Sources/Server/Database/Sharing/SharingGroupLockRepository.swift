//
//  SharingGroupLockRepository.swift
//  Server
//
//  Created by Christopher G Prince on 7/6/19.
//

// Locking facilities for individual sharing groups.

import Foundation
import LoggerAPI
import SyncServerShared

class SharingGroupLock : NSObject, Model {
    static let sharingGroupUUIDKey = "sharingGroupUUID"
    var sharingGroupUUID: String!

    subscript(key:String) -> Any? {
        set {
            switch key {
            case SharingGroupLock.sharingGroupUUIDKey:
                sharingGroupUUID = newValue as! String?

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

class SharingGroupLockRepository: Repository, RepositoryLookup {
    private(set) var db:Database!
    
    required init(_ db:Database) {
        self.db = db
    }
    
    var tableName:String {
        return SharingGroupLockRepository.tableName
    }
    
    static var tableName:String {
        return "SharingGroupLock"
    }
    
    func upcreate() -> Database.TableUpcreateResult {
        let createColumns =
            "(sharingGroupUUID VARCHAR(\(Database.uuidLength)) NOT NULL, " +
            
            // I'm not going to use a foreign key. I believe I've run into locking/deadlock issues in that case.
            "UNIQUE (sharingGroupUUID))"
        
        let result = db.createTableIfNeeded(tableName: "\(tableName)", columnCreateQuery: createColumns)
        return result
    }
    
    enum LookupKey : CustomStringConvertible {
        case sharingGroupUUID(String)
        
        var description : String {
            switch self {
            case .sharingGroupUUID(let sharingGroupUUID):
                return "sharingGroupUUID(\(sharingGroupUUID))"
            }
        }
    }
    
    func lookupConstraint(key:LookupKey) -> String {
        switch key {
        case .sharingGroupUUID(let sharingGroupUUID):
            return "sharingGroupUUID = '\(sharingGroupUUID)'"
        }
    }
    
    enum AddResult {
        case success
        case error(String)
    }
    
    func add(sharingGroupUUID:String) -> AddResult {
        let insert = Database.PreparedStatement(repo: self, type: .insert)
        
        insert.add(fieldName: SharingGroupLock.sharingGroupUUIDKey, value: .string(sharingGroupUUID.lowercased()))
        
        do {
            try insert.run()
            Log.info("Sucessfully created sharing group lock")
            return .success
        }
        catch (let error) {
            Log.error("Could not insert into \(tableName): \(error)")
            return .error("\(error)")
        }
    }

    // Returns true on success.
    func lock(sharingGroupUUID: String) -> Bool {
        return true
#if false
        let query = "SELECT * FROM \(tableName) WHERE \(SharingGroupLock.sharingGroupUUIDKey) = '\(sharingGroupUUID.lowercased())' FOR UPDATE"
        guard let select = Select(db:db, query: query, modelInit: SharingGroupLock.init, ignoreErrors:false) else {
            Log.error("Failed on Select: query: \(query)")
            return false
        }
        
        var foundRow = false
        select.forEachRow { rowModel in
            foundRow = true
        }
        
        if select.forEachRowStatus == nil && foundRow {
            return true
        }
        else {
            Log.error("Failed on forEachRowStatus: \(select.forEachRowStatus!) or foundRow: \(foundRow)")
            return false
        }
#endif
    }
}

