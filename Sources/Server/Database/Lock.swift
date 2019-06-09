//
//  Lock.swift
//  Server
//
//  Created by Christopher Prince on 11/26/16.
//
//

import Foundation

// Provides a distributed lock based on distinct sharingGroupUUID's. Though the sharingGroupUUID usage is independent of database or foreign keys. The usage of sharingGroupUUID is based on the need to lock reads/writes per sharing grouop.

class Lock {
    // Returns true iff successful obtaining lock.
    static func lock(db: Database, sharingGroupUUID: String) -> Bool {
        let timeoutSeconds = 60
        let query = "SELECT GET_LOCK('\(sharingGroupUUID)', \(timeoutSeconds));"
        
        guard let select = Select(db:db, query: query) else {
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
    
    // Returns true iff successful in unlock.
    @discardableResult
    static func unlock(db: Database, sharingGroupUUID:String) -> Bool {
        let query = "SELECT RELEASE_LOCK('\(sharingGroupUUID)')"
        
        guard let select = Select(db:db, query: query) else {
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
