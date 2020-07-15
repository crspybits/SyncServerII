//
//  Database+Lock.swift
//  Server
//
//  Created by Christopher G Prince on 7/12/20.
//

import Foundation
import LoggerAPI

// https://dev.mysql.com/doc/refman/8.0/en/locking-functions.html

extension Database {
    enum DatabaseLockError: Error {
        case failedGetLock(String)
        case failedReleaseLock(String)
    }
    
    // A nil timeout means no timeout; otherwise, gives timeout in seconds.
    func getLock(lockName: String, timeout: UInt? = nil) throws -> Bool {
        var actualTimeout = -1
        if let timeout = timeout {
            actualTimeout = Int(timeout)
        }
        
        let query = "SELECT GET_LOCK('\(lockName)', \(actualTimeout))"

        let result:Int64 = try singleRowNumericQuery(query: query)
        
        if result == 0 {
            return false
        }
        else if result == 1 {
            return true
        }
        
        throw DatabaseLockError.failedGetLock("\(errorMessage()); \(errorCode())")
    }
    
    func releaseLock(lockName: String) throws -> Bool {
        let query = "SELECT RELEASE_LOCK('\(lockName)')"

        let result:Int64 = try singleRowNumericQuery(query: query)
        
        if result == 0 {
            return false
        }
        else if result == 1 {
            return true
        }
        
        throw DatabaseLockError.failedReleaseLock("\(errorMessage()); \(errorCode())")
    }
}
