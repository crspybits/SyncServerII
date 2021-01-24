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

enum RepositoryRemoveResult: RetryRequest {
    case removed(numberRows:Int32)
    case error(String)
    
    case deadlock
    case waitTimeout

    var shouldRetry: Bool {
        if case .deadlock = self {
            return true
        }
        else if case .waitTimeout = self {
            return true
        }
        else {
            return false
        }
    }
}

enum RepositoryLookupResult {
    case found(Model)
    case noObjectFound
    case error(String)
}

extension RepositoryBasics {
    // Remove entire table.
    func remove() -> Bool {
        return db.query(statement: "DROP TABLE \(tableName)")
    }
}

extension RepositoryLookup {
    // Remove row(s) from the table.
    func remove(key:LOOKUPKEY) -> RepositoryRemoveResult {
        let query = "delete from \(tableName) where " + lookupConstraint(key: key)
        
        if db.query(statement: query) {
            let numberRows = db.numberAffectedRows()
            
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
        else if db.errorCode() == Database.deadlockError {
            return .deadlock
        }
        else if db.errorCode() == Database.lockWaitTimeout {
            return .waitTimeout
        }
        else {
            let error = db.error
            Log.error("Could not remove rows from \(tableName): \(error); \(key)")
            return .error("\(error)")
        }
    }
    
    // The lookup should find: a) exactly one object, or b) no objects.
    func lookup<MODEL: Model>(key: LOOKUPKEY, modelInit:@escaping () -> MODEL) -> RepositoryLookupResult {
        let query = "select * from \(tableName) where " + lookupConstraint(key: key)
        
        guard let select = Select(db:db, query: query, modelInit: modelInit, ignoreErrors:false) else {
            return .error("Failed on Select!")
        }
        
        switch select.numberResultRows() {
        case 0:
            Log.debug("No object found!")
            return .noObjectFound
            
        case 1:
            var result:MODEL!
            select.forEachRow { rowModel in
                result = (rowModel as! MODEL)
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

protocol RetryRequest {
    var shouldRetry: Bool {  get }
}


extension Repository {
    func retry<T: RetryRequest>(request: @escaping ()->(T)) -> T {
        let maxNumberRetries = 3
        
        var result = request()
        var count = 1
        
        while result.shouldRetry && count < maxNumberRetries {
            let sleepDuration = TimeInterval(count) * TimeInterval(0.1)
            Log.info("Deadlock found: Retrying after \(sleepDuration)s")
            Thread.sleep(forTimeInterval: sleepDuration)
            result = request()
            count += 1
        }
        
        return result
    }
}
