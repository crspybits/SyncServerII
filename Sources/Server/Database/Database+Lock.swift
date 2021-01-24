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
    
    // Gives the amount of time to wait for the lock if another connection has the lock.
    enum LockTimeout {
        case doNotWait
        case waitForDuration(seconds: UInt)
        case infinite
    }
    
    func getLock(lockName: String, timeout: LockTimeout = .doNotWait) throws -> Bool {
        let actualTimeout: Int
        switch timeout {
        case .doNotWait:
            actualTimeout = 0
        case .waitForDuration(seconds: let seconds):
            actualTimeout = Int(seconds)
        case .infinite:
            actualTimeout = -1
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
    
    @discardableResult
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
