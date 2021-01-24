//
//  DeviceUUIDRepository.swift
//  Server
//
//  Created by Christopher Prince on 2/14/17.
//
//

// Tracks deviceUUID's and their userId's. This is important for security. Also can enable limitations about number of devices per userId.

import Foundation
import LoggerAPI
import ServerShared

class DeviceUUID : NSObject, Model {
    static let userIdKey = "userId"
    var userId: UserId!
    
    static let deviceUUIDKey = "deviceUUID"
    var deviceUUID: String!
    
    subscript(key:String) -> Any? {
        set {
            switch key {
            case DeviceUUID.userIdKey:
                userId = newValue as! UserId?
                
            case DeviceUUID.deviceUUIDKey:
                deviceUUID = newValue as! String?
                
            default:
                assert(false)
            }
        }
        
        get {
            return getValue(forKey: key)
        }
    }

    required override init() {
        super.init()
    }
    
    init(userId: UserId, deviceUUID: String) {
        self.userId = userId
        
        // TODO: *2* Validate that this is a good UUID.
        self.deviceUUID = deviceUUID
    }
}

class DeviceUUIDRepository : Repository, RepositoryLookup {
    private(set) var db:Database!
    
    var maximumNumberOfDeviceUUIDsPerUser:Int? = Configuration.server.maxNumberDeviceUUIDPerUser
    
    required init(_ db:Database) {
        self.db = db
    }
    
    var tableName:String {
        return DeviceUUIDRepository.tableName
    }
    
    static var tableName:String {
        return "DeviceUUID"
    }

    // TODO: *3* We can possibly have the same device used by two different users. E.g., if a user signs in on the device with one set of credentials, then signs out and signs in with a different set of credentials.
    
    func upcreate() -> Database.TableUpcreateResult {
        let createColumns =
            // reference into User table
            "(userId BIGINT NOT NULL, " +

            // identifies a specific mobile device (assigned by app)
            "deviceUUID VARCHAR(\(Database.uuidLength)) NOT NULL, " +
            
            "UNIQUE (deviceUUID))"
        
        return db.createTableIfNeeded(tableName: "\(tableName)", columnCreateQuery: createColumns)
    }
    
    enum LookupKey : CustomStringConvertible {
        case userId(UserId)
        case deviceUUID(String)
        
        var description : String {
            switch self {
            case .userId(let userId):
                return "userId(\(userId))"
            case .deviceUUID(let deviceUUID):
                return "deviceUUID(\(deviceUUID))"
            }
        }
    }
    
    func lookupConstraint(key:LookupKey) -> String {
        switch key {
        case .userId(let userId):
            return "userId = '\(userId)'"
        case .deviceUUID(let deviceUUID):
            return "deviceUUID = '\(deviceUUID)'"
        }
    }
    
    enum DeviceUUIDAddResult {
    case error(String)
    case success
    case exceededMaximumUUIDsPerUser
    }
    
    // Adds a record
    // If maximumNumberOfDeviceUUIDsPerUser != nil, makes sure that the number of deviceUUID's per user doesn't exceed maximumNumberOfDeviceUUIDsPerUser
    func add(deviceUUID:DeviceUUID) -> DeviceUUIDAddResult {
        if deviceUUID.userId == nil || deviceUUID.deviceUUID == nil {
            let message = "One of the model values was nil!"
            Log.error(message)
            return .error(message)
        }
        
        var query = "INSERT INTO \(tableName) (userId, deviceUUID) "
        
        if maximumNumberOfDeviceUUIDsPerUser == nil {
            query += "VALUES (\(deviceUUID.userId!), '\(deviceUUID.deviceUUID!)')"
        }
        else {
            query +=
        "select \(deviceUUID.userId!), '\(deviceUUID.deviceUUID!)' from Dual where " +
        "(select count(*) from \(tableName) where userId = \(deviceUUID.userId!)) < \(maximumNumberOfDeviceUUIDsPerUser!)"
        }

        if db.query(statement: query) {
            if db.numberAffectedRows() == 1 {
                return .success
            }
            else {
                return .exceededMaximumUUIDsPerUser
            }
        }
        else {
            let message = "Could not insert into \(tableName): \(db.error)"
            Log.error(message)
            return .error(message)
        }
    }
}
