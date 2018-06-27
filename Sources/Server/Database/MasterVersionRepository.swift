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
    static let sharingGroupIdKey = "sharingGroupId"
    var sharingGroupId: SharingGroupId!
    
    static let masterVersionKey = "masterVersion"
    var masterVersion: MasterVersionInt!
    
    subscript(key:String) -> Any? {
        set {
            switch key {
            case MasterVersion.sharingGroupIdKey:
                sharingGroupId = newValue as? SharingGroupId
                
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
            "(sharingGroupId BIGINT NOT NULL, " +

            "masterVersion BIGINT NOT NULL, " +

            "FOREIGN KEY (sharingGroupId) REFERENCES \(SharingGroupRepository.tableName)(\(SharingGroup.sharingGroupIdKey)), " +

            "UNIQUE (sharingGroupId))"
        
        return db.createTableIfNeeded(tableName: "\(tableName)", columnCreateQuery: createColumns)
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
    
    // The masterVersion is with respect to the userId
    func lookupConstraint(key:LookupKey) -> String {
        switch key {
        case .sharingGroupId(let sharingGroupId):
            return "sharingGroupId = \(sharingGroupId)"
        }
    }

    func initialize(sharingGroupId:SharingGroupId) -> Bool {
        let query = "INSERT INTO \(tableName) (sharingGroupId, masterVersion) " +
            "VALUES(\(sharingGroupId), \(initialMasterVersion)) "
        
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
    
    // Increments master version for specific userId
    func updateToNext(current:MasterVersion) -> UpdateToNextResult {
    
        let query = "UPDATE \(tableName) SET masterVersion = masterVersion + 1 " +
            "WHERE sharingGroupId = \(current.sharingGroupId!) and " +
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
