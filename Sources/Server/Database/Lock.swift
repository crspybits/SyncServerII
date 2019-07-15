//
//  Lock.swift
//  Server
//
//  Created by Christopher Prince on 11/26/16.
//
//

import Foundation
import LoggerAPI

// Provides a distributed lock based on distinct sharingGroupUUID's. Though the sharingGroupUUID usage is independent of database or foreign keys. The usage of sharingGroupUUID is based on the need to lock reads/writes per sharing grouop.

#if false
class Lock {
    // Returns true iff successful obtaining lock.
    static func lock(db: Database, sharingGroupUUID: String) -> Bool {
        let timeoutSeconds = 60
        let query = "SELECT GET_LOCK('\(sharingGroupUUID)', \(timeoutSeconds));"
        
        Log.debug("Lock.lock: About to lock: Thread.current: \(Thread.current); sharingGroupUUID: \(sharingGroupUUID)")

        guard let select = Select(db:db, query: query) else {
            Log.debug("Lock.lock: Failed to get lock: failed select: Thread.current: \(Thread.current)")
            return false
        }
        
        // See https://dev.mysql.com/doc/refman/5.7/en/locking-functions.html
        switch select.getSingleRowValue() {
        case .success(let successResult):
            guard let result = successResult,
                let intValue = Int("\(result)"), intValue == 1 else {
                Log.debug("Lock.lock: Failed to get lock: result: \(String(describing: successResult)): Thread.current: \(Thread.current)")
                return false
            }
            
            Log.debug("Lock.lock: Successful lock: Thread.current: \(Thread.current)")
            return true
            
        case .error:
            Log.debug("Lock.lock: Failed to get lock: error: Thread.current: \(Thread.current)")
            return false
        }
    }
    
    // Returns true iff successful in unlock.
    @discardableResult
    static func unlock(db: Database, sharingGroupUUID:String) -> Bool {
        let query = "SELECT RELEASE_LOCK('\(sharingGroupUUID)')"
        
        Log.debug("Lock.unlock: About to unlock: Thread.current: \(Thread.current)")

        guard let select = Select(db:db, query: query) else {
            Log.debug("Lock.unlock: Failed to unlock: Thread.current: \(Thread.current)")
            return false
        }
        
        // See https://dev.mysql.com/doc/refman/5.7/en/locking-functions.html
        switch select.getSingleRowValue() {
        case .success(let result):
            guard let result = result, let intValue = Int("\(result)"), intValue == 1 else {
                return false
            }
            
            return true
        case .error:
            return false
        }
    }
}
#endif
