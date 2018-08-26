//
//  MasterVersionRepository.swift
//  Server
//
//  Created by Christopher Prince on 11/26/16.
//
//

// This tracks an overall version of the fileIndex per sharingGroupId.

import Foundation
import SyncServerShared
import LoggerAPI

class MasterVersion : NSObject, Model {
    static let sharingGroupUUIDKey = "sharingGroupUUID"
    var sharingGroupUUID: String!
    
    static let masterVersionKey = "masterVersion"
    var masterVersion: MasterVersionInt!
    
    subscript(key:String) -> Any? {
        set {
            switch key {
            case MasterVersion.sharingGroupUUIDKey:
                sharingGroupUUID = newValue as? String
                
            case MasterVersion.masterVersionKey:
                masterVersion = newValue as? MasterVersionInt
                
            default:
                assert(false)
            }
        }
        
        get {
            return getValue(forKey: key)
        }
    }
}

class MasterVersionRepository : Repository, RepositoryLookup {
    private(set) var db:Database!
    
    required init(_ db:Database) {
        self.db = db
    }
    
    var tableName:String {
        return MasterVersionRepository.tableName
    }
    
    static var tableName:String {
        return "MasterVersion"
    }
    
    let initialMasterVersion = 0

    func upcreate() -> Database.TableUpcreateResult {
        let createColumns =
            "(sharingGroupUUID VARCHAR(\(Database.uuidLength)) NOT NULL, " +

            "masterVersion BIGINT NOT NULL, " +

            "FOREIGN KEY (sharingGroupUUID) REFERENCES \(SharingGroupRepository.tableName)(\(SharingGroup.sharingGroupUUIDKey)), " +

            "UNIQUE (sharingGroupUUID))"
        
        return db.createTableIfNeeded(tableName: "\(tableName)", columnCreateQuery: createColumns)
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
    
    // The masterVersion is with respect to the userId
    func lookupConstraint(key:LookupKey) -> String {
        switch key {
        case .sharingGroupUUID(let sharingGroupUUID):
            return "sharingGroupUUID = '\(sharingGroupUUID)'"
        }
    }

    func initialize(sharingGroupUUID:String) -> Bool {
        let query = "INSERT INTO \(tableName) (sharingGroupUUID, masterVersion) " +
            "VALUES('\(sharingGroupUUID)', \(initialMasterVersion)) "
        
        if db.connection.query(statement: query) {
            return true
        }
        else {
            let error = db.error
            Log.error("Could not initialize MasterVersion: \(error)")
            return false
        }
    }
    
    enum UpdateToNextResult {
    case error(String)
    case didNotMatchCurrentMasterVersion
    case success
    }
    
    // Increments master version for specific sharingGroupId
    func updateToNext(current:MasterVersion) -> UpdateToNextResult {
    
        let query = "UPDATE \(tableName) SET masterVersion = masterVersion + 1 " +
            "WHERE sharingGroupUUID = '\(current.sharingGroupUUID!)' and " +
            "masterVersion = \(current.masterVersion!)"
        
        if db.connection.query(statement: query) {
            if db.connection.numberAffectedRows() == 1 {
                return UpdateToNextResult.success
            }
            else {
                return UpdateToNextResult.didNotMatchCurrentMasterVersion
            }
        }
        else {
            let message = "Could not updateToNext MasterVersion: \(db.error)"
            Log.error(message)
            return UpdateToNextResult.error(message)
        }
    }
}
