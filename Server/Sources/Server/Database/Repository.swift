//
//  Repository.swift
//  Server
//
//  Created by Christopher Prince on 11/26/16.
//
//

import Foundation
import PerfectLib

protocol Repository {
    associatedtype LOOKUPKEY

    static var tableName:String {get}

    // Create the database table.
    static func create() -> Database.TableCreationResult
    
    // Returns a constraint for a WHERE clause in mySQL based on the key
    static func lookupConstraint(key:LOOKUPKEY) -> String
}

enum RepositoryRemoveResult {
    case removed
    case error(String)
}

enum RepositoryLookupResult {
    case found(Model)
    case noObjectFound
    case error(String)
}

extension Repository {
    // Remove entire table.
    static func remove() -> Bool {
        return Database.session.connection.query(statement: "DROP TABLE \(tableName)")
    }
    
    // Remove a single row from the table.
    static func remove(key:LOOKUPKEY) -> RepositoryRemoveResult {
        let query = "delete from \(tableName) where " + lookupConstraint(key: key)
        
        if Database.session.connection.query(statement: query) {
            // TODO: Ensure that only a single row was affected.
            Log.info(message: "Successfully removed user: \(key)")
            return .removed
        }
        else {
            let error = Database.session.error
            Log.error(message: "Could not remove user: \(error)")
            return .error("\(error)")
        }
    }
    
    static func lookup<MODEL: Model>(key: LOOKUPKEY, modelInit:@escaping () -> MODEL) -> RepositoryLookupResult {
        let query = "select * from \(tableName) where " + lookupConstraint(key: key)
        let select = Select(query: query, modelInit: modelInit, ignoreErrors:false)
        
        switch select.numberResultRows() {
        case 0:
            return .noObjectFound
            
        case 1:
            var result:MODEL!
            select.forEachRow { rowModel in
                result = rowModel as! MODEL
            }
            
            if select.forEachRowStatus != nil {
                let error = "Error: \(select.forEachRowStatus!) in Select forEachRow"
                Log.error(message: error)
                return .error(error)
            }
            
            return .found(result)

        default:
            let error = "Error: \(select.numberResultRows()) in Select result: More than one object found!"
            Log.error(message: error)
            return .error(error)
        }
    }
}
