//
//  MasterVersionRepository.swift
//  Server
//
//  Created by Christopher Prince on 11/26/16.
//
//

// This tracks an overall version of the fileIndex per userId.

import Foundation
import PerfectLib

class MasterVersion : NSObject, Model {
    static let userIdKey = "userId"
    var userId: UserId!
    
    static let masterVersionKey = "masterVersion"
    var masterVersion: MasterVersionInt!
    
    subscript(key:String) -> Any? {
        set {
            switch key {
            case MasterVersion.userIdKey:
                userId = newValue as! UserId!
                
            case MasterVersion.masterVersionKey:
                masterVersion = newValue as! MasterVersionInt!
                
            default:
                assert(false)
            }
        }
        
        get {
            return getValue(forKey: key)
        }
    }
}

class MasterVersionRepository : Repository {
    private(set) var db:Database!
    
    init(_ db:Database) {
        self.db = db
    }
    
    var tableName:String {
        return "MasterVersion"
    }
    
    let initialMasterVersion = 0

    func create() -> Database.TableCreationResult {
        let createColumns =
            // reference into User table
            "(userId BIGINT NOT NULL, " +

            "masterVersion BIGINT NOT NULL, " +

            "UNIQUE (userId))"
        
        return db.createTableIfNeeded(tableName: "\(tableName)", columnCreateQuery: createColumns)
    }
    
    enum LookupKey : CustomStringConvertible {
        case userId(UserId)
        
        var description : String {
            switch self {
            case .userId(let userId):
                return "userId(\(userId))"
            }
        }
    }
    
    // The masterVersion is with respect to the userId
    func lookupConstraint(key:LookupKey) -> String {
        switch key {
        case .userId(let userId):
            return "userId = '\(userId)'"
        }
    }

    func initialize(userId:UserId) -> Bool {
        let query = "INSERT INTO \(tableName) (userId, masterVersion) " +
            "VALUES(\(userId), \(initialMasterVersion)) "
        
        if db.connection.query(statement: query) {
            return true
        }
        else {
            let error = db.error
            Log.error(message: "Could not initialize MasterVersion: \(error)")
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
            "WHERE userId = \(current.userId!) and " +
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
            Log.error(message: message)
            return UpdateToNextResult.error(message)
        }
    }
}
