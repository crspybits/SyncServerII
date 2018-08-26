//
//  LockRepository.swift
//  Server
//
//  Created by Christopher Prince on 11/26/16.
//
//

// Enables short duration locks to be held while info in the UploadRepository is transfered to the FileIndexRepository. This lock works in a somewhat non-obvious manner. Due to the blocking nature of transactions in InnoDB with row-level locking, a lock held by one server request for a specific sharingGroupId in a transaction will block another server request attempting to obtain the same lock for the same sharingGroupId.

import Foundation
import SyncServerShared
import LoggerAPI

class Lock : NSObject, Model {
    static let sharingGroupUUIDKey = "sharingGroupUUID"
    var sharingGroupUUID: String!
    
    static let deviceUUIDKey = "deviceUUID"
    var deviceUUID: String!
    
    static let expiryKey = "expiry"
    var expiry: Date!
    
    // This expiry mechanism ought never to actually be needed. Since, a lock will be rolled back should a server request fail, we should never have to be concerned about having stale locks. I'm keeping expiries here just as an insurance plan-- e.g., in case a software glitch causes a lock to be retained after a server request has been finished.
    static let expiryDuration:TimeInterval = 60

    subscript(key:String) -> Any? {
        set {
            switch key {
            case Lock.sharingGroupUUIDKey:
                sharingGroupUUID = newValue as? String
                
            case Lock.deviceUUIDKey:
                deviceUUID = newValue as? String
                
            case Lock.expiryKey:
                expiry = newValue as? Date
                
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
    
    init(sharingGroupUUID: String, deviceUUID: String,
        expiryDuration:TimeInterval = Lock.expiryDuration) {
        self.sharingGroupUUID = sharingGroupUUID
        self.deviceUUID = deviceUUID
        let calendar = Calendar.current
        expiry = calendar.date(byAdding: .second, value: Int(expiryDuration), to: Date())!
    }
}

class LockRepository : Repository, RepositoryLookup {
    private(set) var db:Database!
    
    required init(_ db:Database) {
        self.db = db
    }
    
    let dateFormat = DateExtras.DateFormat.DATETIME

    var tableName:String {
        return LockRepository.tableName
    }
    
    static var tableName:String {
        // Apparently the table name Lock is special-- get an error if we use it.
        return "ShortLocks"
    }

    func upcreate() -> Database.TableUpcreateResult {
        let createColumns =
            "(sharingGroupUUID VARCHAR(\(Database.uuidLength)) NOT NULL, " +

            // identifies a specific mobile device (assigned by app)
            "deviceUUID VARCHAR(\(Database.uuidLength)) NOT NULL, " +

            "expiry \(dateFormat.rawValue), " +

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
    
    func lookupConstraint(key:LookupKey) -> String {
        switch key {
        case .sharingGroupUUID(let sharingGroupUUID):
            return "sharingGroupUUID = '\(sharingGroupUUID)'"
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
        if lock.sharingGroupUUID == nil || lock.deviceUUID == nil || lock.expiry == nil {
            Log.error("One of the model values was nil!")
            return .modelValueWasNil
        }
        
        if removeStale {
            if removeStaleLock(forSharingGroupUUID: lock.sharingGroupUUID!) == nil {
                Log.error("Error removing stale locks!")
                return .errorRemovingStaleLocks
            }
        }
        
        let expiry = DateExtras.date(lock.expiry, toFormat: dateFormat)
        
        // TODO: *2* It would be good to specify the expiry time dynamically if possible-- this insert can block. e.g., NOW() + INTERVAL 15 DAY
        // It is conceptually possible for the block to wake up and the lock already to be expired.
        
        let query = "INSERT INTO \(tableName) (sharingGroupUUID, deviceUUID, expiry) VALUES('\(lock.sharingGroupUUID!)', '\(lock.deviceUUID!)', '\(expiry)');"
        
        if db.connection.query(statement: query) {
            Log.info("Sucessfully obtained lock!!")
            return .success
        }
        else if db.connection.errorCode() == Database.duplicateEntryForKey {
            return .lockAlreadyHeld
        }
        else {
            let error = db.error
            Log.error("Could not insert into \(tableName): \(error)")
            return .otherError
        }
    }
    
    // Omit the userId parameter to remove all stale locks.
    // Returns the number of stale locks that were actually removed, or nil if there was an error.
    func removeStaleLock(forSharingGroupUUID sharingGroupUUID:String? = nil) -> Int? {
        let staleDate = DateExtras.date(Date(), toFormat: dateFormat)
        
        var sharingGroupUUIDConstraint = ""
        if sharingGroupUUID != nil {
            sharingGroupUUIDConstraint = "sharingGroupUUID = '\(sharingGroupUUID!)' and "
        }
        
        let query = "DELETE FROM \(tableName) WHERE \(sharingGroupUUIDConstraint) expiry < '\(staleDate)'"
        
        if db.connection.query(statement: query) {
            let numberLocksRemoved = Int(db.connection.numberAffectedRows())
            Log.info("Number of stale locks removed: \(numberLocksRemoved)")
            return numberLocksRemoved
        }
        else {
            let error = db.error
            Log.error("Could not remove stale lock: \(error)")
            return nil
        }
    }
    
    @discardableResult
    func unlock(sharingGroupUUID:String) -> Bool {
        let query = "DELETE FROM \(tableName) WHERE sharingGroupUUID = '\(sharingGroupUUID)'"
        
        if db.connection.query(statement: query) {
            Log.info("Sucessfully released lock!!")
            return true
        }
        else {
            let error = db.error
            Log.error("Could not unlock: \(error)")
            return false
        }
    }
}
