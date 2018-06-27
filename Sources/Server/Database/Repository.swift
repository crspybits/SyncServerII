//
//  Repository.swift
//  Server
//
//  Created by Christopher Prince on 11/26/16.
//
//

import Foundation
import LoggerAPI

protocol RepositoryBasics {
    var db:Database! {get}

    var tableName:String {get}
    static var tableName:String {get}
}

protocol RepositoryLookup : RepositoryBasics {
    associatedtype LOOKUPKEY

    // Returns a constraint for a WHERE clause in mySQL based on the key
    func lookupConstraint(key:LOOKUPKEY) -> String
}

protocol Repository {
    init(_ db: Database)
    
    // If the table is present, and it's structure needs updating, update it.
    // If it's absent, create it.
    func upcreate() -> Database.TableUpcreateResult
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

extension RepositoryBasics {
    // Remove entire table.
    func remove() -> Bool {
        return db.connection.query(statement: "DROP TABLE \(tableName)")
    }
}

extension RepositoryLookup {
    // Remove row(s) from the table.
    func remove(key:LOOKUPKEY) -> RepositoryRemoveResult {
        let query = "delete from \(tableName) where " + lookupConstraint(key: key)
        
        if db.connection.query(statement: query) {
            let numberRows = db.connection.numberAffectedRows()
            
            var initialMessage:String
            if numberRows == 0 {
                initialMessage = "Did not remove any rows"
            }
            else {
                initialMessage = "Successfully removed \(numberRows) row(s)"
            }
            Log.info("\(initialMessage) from \(tableName): \(key)")
            
            return .removed(numberRows:Int32(numberRows))
        }
        else {
            let error = db.error
            Log.error("Could not remove rows from \(tableName): \(error)")
            return .error("\(error)")
        }
    }
    
    func lookup<MODEL: Model>(key: LOOKUPKEY, modelInit:@escaping () -> MODEL) -> RepositoryLookupResult {
        let query = "select * from \(tableName) where " + lookupConstraint(key: key)
        let select = Select(db:db, query: query, modelInit: modelInit, ignoreErrors:false)
        
        switch select.numberResultRows() {
        case 0:
            Log.debug("No object found!")
            return .noObjectFound
            
        case 1:
            var result:MODEL!
            select.forEachRow { rowModel in
                result = rowModel as! MODEL
            }
            
            if select.forEachRowStatus != nil {
                let error = "Error: \(select.forEachRowStatus!) in Select forEachRow"
                Log.error(error)
                return .error(error)
            }
            
            Log.debug("Found result!")
            return .found(result)

        default:
            let error = "Error: \(select.numberResultRows()) in Select result: More than one object found!"
            Log.error(error)
            return .error(error)
        }
    }
}

extension Repository {
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
    
    func getInsertFieldValueAndName(fieldValue: Any?, fieldName:String, fieldIsString:Bool = true) -> (queryFieldValue:String, queryFieldName:String) {
        
        var queryFieldName = ""
        var queryFieldValue = ""
        if fieldValue != nil {
            queryFieldName = ", \(fieldName) "

            if fieldIsString {
                queryFieldValue = ", '\(fieldValue!)' "
            }
            else {
                queryFieldValue = ", \(fieldValue!) "
            }
        }
        
        return (queryFieldValue, queryFieldName)
    }
}
