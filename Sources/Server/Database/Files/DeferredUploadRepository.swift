//
//  DeferredUploadRepository.swift
//  Server
//
//  Created by Christopher G Prince on 7/11/20.
//

import Foundation
import LoggerAPI

class DeferredUpload : NSObject, Model {
    enum Status: String {
        case pending
        case completed
        case error
        
        static var maxCharacterLength: Int {
            return 20
        }
    }
    
    static let deferredUploadIdKey = "deferredUploadId"
    var deferredUploadId:Int64!
    
    static let sharingGroupUUIDKey = "sharingGroupUUID"
    var sharingGroupUUID:String?
    
    static let fileGroupUUIDKey = "fileGroupUUID"
    // Not all files have to be associated with a file group.
    var fileGroupUUID:String?
    
    static let statusKey = "status"
    var status:Status!
    
    subscript(key:String) -> Any? {
        set {
            switch key {
            case DeferredUpload.deferredUploadIdKey:
                deferredUploadId = newValue as? Int64

            case DeferredUpload.sharingGroupUUIDKey:
                sharingGroupUUID = newValue as? String
                
            case DeferredUpload.fileGroupUUIDKey:
                fileGroupUUID = newValue as? String

            case DeferredUpload.statusKey:
                status = newValue as? Status
                
            default:
                assert(false)
            }
        }
        
        get {
            return getValue(forKey: key)
        }
    }
    
    func typeConvertersToModel(propertyName:String) -> ((_ propertyValue:Any) -> Any?)? {
        switch propertyName {
            case DeferredUpload.statusKey:
                return {(x:Any) -> Any? in
                    guard let rawValue = x as? String else {
                        return nil
                    }
                    return Status(rawValue: rawValue)
                }
            
            default:
                return nil
        }
    }
}

class DeferredUploadRepository : Repository, RepositoryLookup {
    private(set) var db:Database!

    required init(_ db:Database) {
        self.db = db
    }
    
    var tableName:String {
        return DeferredUploadRepository.tableName
    }
    
    static var tableName:String {
        return "DeferredUpload"
    }
    
    func upcreate() -> Database.TableUpcreateResult {
        let createColumns =
            "(deferredUploadId BIGINT NOT NULL AUTO_INCREMENT, " +
            
            "sharingGroupUUID VARCHAR(\(Database.uuidLength)) NOT NULL, " +

            "fileGroupUUID VARCHAR(\(Database.uuidLength)), " +

            "status VARCHAR(\(DeferredUpload.Status.maxCharacterLength)) NOT NULL, " +
            
            "UNIQUE (deferredUploadId))"
        
        let result = db.createTableIfNeeded(tableName: "\(tableName)", columnCreateQuery: createColumns)
        
        switch result {
        case .success(.alreadyPresent):
            break
            
        default:
            break
        }
        
        return result
    }
    
    enum LookupKey : CustomStringConvertible {
        case deferredUploadId(Int64)
        
        var description : String {
            switch self {
            case .deferredUploadId(let deferredUploadId):
                return "deferredUploadId(\(deferredUploadId))"
            }
        }
    }
    
    func lookupConstraint(key:LookupKey) -> String {
        switch key {
        case .deferredUploadId(let deferredUploadId):
            return "deferredUploadId = '\(deferredUploadId)'"
        }
    }
    
    enum AddResult: RetryRequest {
        case success(deferredUploadId:Int64)
        case otherError(String)
        
        case deadlock
        case waitTimeout
        
        var shouldRetry: Bool {
            if case .deadlock = self {
                return true
            }
            if case .waitTimeout = self {
                return true
            }
            else {
                return false
            }
        }
    }
    
    // deferredUploadId in the model is ignored and the automatically generated deferredUploadId is returned if the add is successful.
    func add(_ deferredUpload:DeferredUpload) -> AddResult {
        let insert = Database.PreparedStatement(repo: self, type: .insert)
        
        insert.add(fieldName: DeferredUpload.sharingGroupUUIDKey, value: .stringOptional(deferredUpload.sharingGroupUUID))
        insert.add(fieldName: DeferredUpload.fileGroupUUIDKey, value: .stringOptional(deferredUpload.fileGroupUUID))
        insert.add(fieldName: DeferredUpload.statusKey, value: .stringOptional(deferredUpload.status?.rawValue))

        do {
            try insert.run()
            Log.info("Sucessfully created DeferredUpload row")
            return .success(deferredUploadId: db.lastInsertId())
        }
        catch (let error) {
            Log.info("Failed inserting DeferredUpload row: \(db.errorCode()); \(db.errorMessage())")
            
            if db.errorCode() == Database.deadlockError {
                return .deadlock
            }
            else if db.errorCode() == Database.lockWaitTimeout {
                return .waitTimeout
            }
            else {
                let message = "Could not insert into \(tableName): \(error)"
                Log.error(message)
                return .otherError(message)
            }
        }
    }
    
    func update(_ deferredUpload: DeferredUpload) -> Bool {
        guard let deferredUploadId = deferredUpload.deferredUploadId else {
            Log.error("update: Nil deferredUploadId")
            return false
        }
        
        let update = Database.PreparedStatement(repo: self, type: .update)
        
        update.add(fieldName: DeferredUpload.statusKey, value: .stringOptional(deferredUpload.status?.rawValue))
        
        update.where(fieldName: DeferredUpload.deferredUploadIdKey, value: .int64(deferredUploadId))
        
        do {
            try update.run()
        }
        catch (let error) {
            Log.error("Failed updating DeferredUpload: \(error)")
            return false
        }
        
        return true
    }
    
    // A nil result indicates an error. No rows in the query is returned as an empty array.
    func select(rowsWithStatus status: DeferredUpload.Status) -> [DeferredUpload]? {
        let query = "select * from \(tableName) where \(DeferredUpload.statusKey)='\(status.rawValue)'"

        guard let select = Select(db:db, query: query, modelInit: DeferredUpload.init, ignoreErrors:false) else {
            Log.error("select: Failed calling constructor")
            return nil
        }

        var result:[DeferredUpload] = []
        var error = false
        
        select.forEachRow { rowModel in
            guard let rowModel = rowModel as? DeferredUpload else {
                error = true
                return
            }
            
            result.append(rowModel)
        }
        
        if select.forEachRowStatus == nil && !error {
            return result
        }
        else {
            return nil
        }
    }
}

