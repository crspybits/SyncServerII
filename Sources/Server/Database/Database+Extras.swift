//
//  Database+Extras.swift
//  Server
//
//  Created by Christopher G Prince on 7/12/20.
//

import Foundation

extension Database {
    enum DatabaseError: Error {
        case singleRowNumericQuery(String)
    }
    
    private class Result<T>: Model {
        required init() {}
        
        var value: T?
        
        subscript(key: String) -> Any? {
            set {
                value = newValue as? T
            }
            get {
                return getValue(forKey: key)
            }
        }
    }
    
    // Run a query which gives a single result of type T.
    func singleRowNumericQuery<T>(query: String) throws -> T {
        guard let select = Select(db: self, query: query, modelInit: Result<T>.init, ignoreErrors: false) else {
            throw DatabaseError.singleRowNumericQuery("Failed on select")
        }
        
        var error: Error?
        var result: T?
        select.forEachRow { model in
            guard let model = model as? Result<T> else {
                error = DatabaseError.singleRowNumericQuery("Failed on model conversion")
                return
            }
            
            guard let value = model.value else {
                error = DatabaseError.singleRowNumericQuery("Failed getting value")
                return
            }
            
            result = value
            return
        }
        
        if let forEachRowStatus = select.forEachRowStatus {
            throw DatabaseError.singleRowNumericQuery("Failed forEachRowStatus: \(forEachRowStatus)")
        }
        
        if let err = error {
            throw err
        }
        
        if let res = result {
            return res
        }
        else {
            throw DatabaseError.singleRowNumericQuery("\(errorMessage()); \(errorCode())")
        }
    }
}
