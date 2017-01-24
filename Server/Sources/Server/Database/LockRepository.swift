//
//  LockRepository.swift
//  Server
//
//  Created by Christopher Prince on 11/26/16.
//
//

// Enables short duration locks to be held while info in the UploadRepository is transfered to the FileIndexRepository.

import Foundation
import PerfectLib

class Lock : NSObject, Model {
    var userId: Int64!
    var deviceUUID: String!
    var expiry: Date!
    
    static let additionalExpiryDuration:TimeInterval = 60

    override init() {
        super.init()
    }
    
    init(userId: Int64, deviceUUID: String,
        additionalExpiryDuration:TimeInterval = Lock.additionalExpiryDuration) {
        self.userId = userId
        self.deviceUUID = deviceUUID
        let calendar = Calendar.current
        expiry = calendar.date(byAdding: .second, value: Int(additionalExpiryDuration), to: Date())!
    }
}

class LockRepository : Repository {
    static let dateFormat = Database.MySQLDateFormat.DATETIME

    static var tableName:String {
        // Apparently the table name Lock is special-- get an error if we use it.
        return "ShortLocks"
    }

    static func create() -> Database.TableCreationResult {
        let createColumns =
            // reference into User table
            "(userId BIGINT NOT NULL, " +

            // identifies a specific mobile device (assigned by app)
            "deviceUUID VARCHAR(\(Database.uuidLength)) NOT NULL, " +

            "expiry \(dateFormat.rawValue), " +
            
            "UNIQUE (userId));"
        
        return Database.session.createTableIfNeeded(tableName: "\(tableName)", columnCreateQuery: createColumns)
    }
    
    enum LookupKey : CustomStringConvertible {
        case userId(Int64)
        
        var description : String {
            switch self {
            case .userId(let userId):
                return "userId(\(userId))"
            }
        }
    }
    
    static func lookupConstraint(key:LookupKey) -> String {
        switch key {
        case .userId(let userId):
            return "userId = '\(userId)'"
        }
    }
    
    // removeStale indicates whether to remove any lock, held by the user, past its expiry prior to attempting to obtain lock.
    static func lock(lock:Lock, removeStale:Bool = true) -> Bool {
        if lock.userId == nil || lock.deviceUUID == nil || lock.expiry == nil {
            Log.error(message: "One of the model values was nil!")
            return false
        }
        
        if removeStale {
            if !removeStaleLock(forUserId: lock.userId!) {
                Log.error(message: "Error removing stale locks!")
                return false
            }
        }
        
        let expiry = Database.date(lock.expiry, toFormat: dateFormat)
        
        let query = "INSERT INTO \(tableName) (userId, deviceUUID, expiry) VALUES(\(lock.userId!), '\(lock.deviceUUID!)', '\(expiry)');"
        
        if Database.session.connection.query(statement: query) {
            return true
        }
        else {
            let error = Database.session.error
            Log.error(message: "Could not insert into \(tableName): \(error)")
            return false
        }
    }
    
    // Omit the userId parameter to remove all stale locks.
    // TODO: It would be good to return whether or not any stale locks were actually removed. e.g., the number of locks removed.
    static func removeStaleLock(forUserId userId:Int64? = nil) -> Bool {
        let staleDate = Database.date(Date(), toFormat: dateFormat)
        
        var userIdConstraint = ""
        if userId != nil {
            userIdConstraint = "userId = \(userId!) and "
        }
        
        let query = "DELETE FROM \(tableName) WHERE \(userIdConstraint) expiry < '\(staleDate)'"
        
        if Database.session.connection.query(statement: query) {
            return true
        }
        else {
            let error = Database.session.error
            Log.error(message: "Could not remove stale lock: \(error)")
            return false
        }
    }
    
    static func unlock(userId:Int64) -> Bool {
        let query = "DELETE FROM \(tableName) WHERE userId = \(userId)"
        
        if Database.session.connection.query(statement: query) {
            return true
        }
        else {
            let error = Database.session.error
            Log.error(message: "Could not unlock: \(error)")
            return false
        }
    }
}
