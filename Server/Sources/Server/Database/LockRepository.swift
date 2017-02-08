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
    var userId: UserId!
    var deviceUUID: String!
    var expiry: Date!
    
    static let expiryDuration:TimeInterval = 60

    override init() {
        super.init()
    }
    
    init(userId: UserId, deviceUUID: String,
        expiryDuration:TimeInterval = Lock.expiryDuration) {
        self.userId = userId
        self.deviceUUID = deviceUUID
        let calendar = Calendar.current
        expiry = calendar.date(byAdding: .second, value: Int(expiryDuration), to: Date())!
    }
}

class LockRepository : Repository {
    private(set) var db:Database!
    
    init(_ db:Database) {
        self.db = db
    }
    
    let dateFormat = Database.MySQLDateFormat.DATETIME

    var tableName:String {
        // Apparently the table name Lock is special-- get an error if we use it.
        return "ShortLocks"
    }

    func create() -> Database.TableCreationResult {
        let createColumns =
            // reference into User table
            "(userId BIGINT NOT NULL, " +

            // identifies a specific mobile device (assigned by app)
            "deviceUUID VARCHAR(\(Database.uuidLength)) NOT NULL, " +

            "expiry \(dateFormat.rawValue), " +
            
            "UNIQUE (userId));"
        
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
    
    func lookupConstraint(key:LookupKey) -> String {
        switch key {
        case .userId(let userId):
            return "userId = '\(userId)'"
        }
    }
    
    // removeStale indicates whether to remove any lock, held by the user, past its expiry prior to attempting to obtain lock.
    func lock(lock:Lock, removeStale:Bool = true) -> Bool {
        if lock.userId == nil || lock.deviceUUID == nil || lock.expiry == nil {
            Log.error(message: "One of the model values was nil!")
            return false
        }
        
        if removeStale {
            if removeStaleLock(forUserId: lock.userId!) == nil {
                Log.error(message: "Error removing stale locks!")
                return false
            }
        }
        
        let expiry = Database.date(lock.expiry, toFormat: dateFormat)
        
        let query = "INSERT INTO \(tableName) (userId, deviceUUID, expiry) VALUES(\(lock.userId!), '\(lock.deviceUUID!)', '\(expiry)');"
        
        if db.connection.query(statement: query) {
            return true
        }
        else {
            let error = db.error
            Log.error(message: "Could not insert into \(tableName): \(error)")
            return false
        }
    }
    
    // Omit the userId parameter to remove all stale locks.
    // Returns the number of stale locks that were actually removed, or nil if there was an error.
    func removeStaleLock(forUserId userId:UserId? = nil) -> Int? {
        let staleDate = Database.date(Date(), toFormat: dateFormat)
        
        var userIdConstraint = ""
        if userId != nil {
            userIdConstraint = "userId = \(userId!) and "
        }
        
        let query = "DELETE FROM \(tableName) WHERE \(userIdConstraint) expiry < '\(staleDate)'"
        
        if db.connection.query(statement: query) {
            let numberLocksRemoved = Int(db.connection.numberAffectedRows())
            Log.info(message: "Number of locks removed: \(numberLocksRemoved)")
            return numberLocksRemoved
        }
        else {
            let error = db.error
            Log.error(message: "Could not remove stale lock: \(error)")
            return nil
        }
    }
    
    func unlock(userId:UserId) -> Bool {
        let query = "DELETE FROM \(tableName) WHERE userId = \(userId)"
        
        if db.connection.query(statement: query) {
            return true
        }
        else {
            let error = db.error
            Log.error(message: "Could not unlock: \(error)")
            return false
        }
    }
}
