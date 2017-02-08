//
//  MasterVersionRepository.swift
//  Server
//
//  Created by Christopher Prince on 11/26/16.
//
//

import Foundation
import PerfectLib

class MasterVersion : NSObject, Model {
    var userId: UserId!
    var masterVersion: MasterVersionInt!
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

    // For a new record, gives the version: initialMasterVersion
    // For existing records, adds 1 to the version.
    func upsert(userId:UserId) -> Bool {
        let query = "INSERT INTO \(tableName) (userId, masterVersion) " +
            "VALUES(\(userId), \(initialMasterVersion)) " +
            "ON DUPLICATE KEY UPDATE masterVersion = masterVersion + 1 "
        
        if db.connection.query(statement: query) {
            return true
        }
        else {
            let error = db.error
            Log.error(message: "Could not upsert MasterVersion: \(error)")
            return false
        }
    }
}
