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
    
    var db:Database! {get}

    var tableName:String {get}

    // Create the database table.
    func create() -> Database.TableCreationResult
    
    // Returns a constraint for a WHERE clause in mySQL based on the key
    func lookupConstraint(key:LOOKUPKEY) -> String
}

enum RepositoryRemoveResult {
    case removed(numberRows:Int32)
    case error(String)
}

enum RepositoryLookupResult {
    case found(Model)
    case noObjectFound
    case error(String)
}

extension Repository {
    // Remove entire table.
    func remove() -> Bool {
        return db.connection.query(statement: "DROP TABLE \(tableName)")
    }
    
    // Remove row(s) from the table.
    func remove(key:LOOKUPKEY) -> RepositoryRemoveResult {
        let query = "delete from \(tableName) where " + lookupConstraint(key: key)
        
        if db.connection.query(statement: query) {
            Log.info(message: "Successfully removed row(s) from \(tableName): \(key)")
            return .removed(
                numberRows:Int32(db.connection.numberAffectedRows()))
        }
        else {
            let error = db.error
            Log.error(message: "Could not remove rows from \(tableName): \(error)")
            return .error("\(error)")
        }
    }
    
    func lookup<MODEL: Model>(key: LOOKUPKEY, modelInit:@escaping () -> MODEL) -> RepositoryLookupResult {
        let query = "select * from \(tableName) where " + lookupConstraint(key: key)
        let select = Select(db:db, query: query, modelInit: modelInit, ignoreErrors:false)
        
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
    
    func getUpdateFieldSetter(fieldValue: Any?, fieldName:String, fieldIsString:Bool = true) -> String {
        
        var fieldSetter = ""
        if fieldValue != nil {
            fieldSetter = ", \(fieldName) = "
            if fieldIsString {
                fieldSetter += "'\(fieldValue!)' "
            }
            else {
                fieldSetter += "\(fieldValue!) "
            }
        }
        
        return fieldSetter
    }
}
