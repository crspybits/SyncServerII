//
//  LockRepository.swift
//  Server
//
//  Created by Christopher Prince on 11/26/16.
//
//

// Enables short duration locks to be held while info in the UploadRepository is transfered to the FileIndexRepository. This lock works in a somewhat non-obvious manner. Due to the blocking nature of transactions in InnoDB with row-level locking, a lock held by one server request for a specific userId in a transaction will block another server request attempting to obtain the same lock for the same userId.

import Foundation
import PerfectLib

class Lock : NSObject, Model {
    var userId: UserId!
    var deviceUUID: String!
    var expiry: Date!
    
    // This expiry mechanism ought never to actually be needed. Since, a lock will be rolled back should a server request fail, we should never have to be concerned about having stale locks. I'm keeping expiries here just as an insurance plan-- e.g., in case a software glitch causes a lock to be retained after a server request has been finished.
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
    
    func lookupConstraint(key:LookupKey) -> String {
        switch key {
        case .userId(let userId):
            return "userId = '\(userId)'"
        }
    }
    
    enum LockAttemptResult : Error {
    case success
    case modelValueWasNil
    case errorRemovingStaleLocks
    
    // This represents an error condition. Due to transactions, we should always block when another server request has a lock for a particular userId; we should never be in a state where we observe that a lock is already held.
    case lockAlreadyHeld
    
    case otherError
    }
    
    // removeStale indicates whether to remove any lock, held by the user, past its expiry prior to attempting to obtain lock.
    func lock(lock:Lock, removeStale:Bool = true) -> LockAttemptResult {
        if lock.userId == nil || lock.deviceUUID == nil || lock.expiry == nil {
            Log.error(message: "One of the model values was nil!")
            return .modelValueWasNil
        }
        
        if removeStale {
            if removeStaleLock(forUserId: lock.userId!) == nil {
                Log.error(message: "Error removing stale locks!")
                return .errorRemovingStaleLocks
            }
        }
        
        let expiry = Database.date(lock.expiry, toFormat: dateFormat)
        
        // TODO: *2* It would be good to specify the expiry time dynamically if possible-- this insert can block. e.g., NOW() + INTERVAL 15 DAY
        // It is conceptually possible for the block to wake up and the lock already to be expired.
        
        let query = "INSERT INTO \(tableName) (userId, deviceUUID, expiry) VALUES(\(lock.userId!), '\(lock.deviceUUID!)', '\(expiry)');"
        
        if db.connection.query(statement: query) {
            return .success
        }
        else if db.connection.errorCode() == Database.duplicateEntryForKey {
            return .lockAlreadyHeld
        }
        else {
            let error = db.error
            Log.error(message: "Could not insert into \(tableName): \(error)")
            return .otherError
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
