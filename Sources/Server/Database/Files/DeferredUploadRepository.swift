//
//  DeferredUploadRepository.swift
//  Server
//
//  Created by Christopher G Prince on 7/11/20.
//

import Foundation
import LoggerAPI
import ServerShared

/* This table represents two kinds of things:
1) In pending states, it represents an upload that needs to be processed asynchronously by the Uploader.
2) In .completed or .error states it is used by the GetUploadResults endpoint to report on the completion of Uploader asynchronously processing.

A single row in this table is used to represent (a) a single upload deletion, (b) the last file upload in a batch of uploads (either 1 of 1, or the last in an N of M batch).
 */

class DeferredUpload : NSObject, Model {
    required override init() {
        super.init()
    }

    static let deferredUploadIdKey = "deferredUploadId"
    var deferredUploadId:Int64!
    
    // The signed in userId of the user creating the DeferredUpload.
    static let userIdKey = "userId"
    var userId:UserId!
    
    // Assigned after the DeferredUpload completed-- so we can know when to remove this row.
    static let completionDateKey = "completionDate"
    var completionDate:Date!
    
    static let sharingGroupUUIDKey = "sharingGroupUUID"
    var sharingGroupUUID:String!
    
    /* For a pendingDeletion:
        a) if this is non-nil, then there is no associated Upload record. It indicates we're deleting all files in a file group;
        b) if it's nil, then there is an associated Upload record-- this is a deletion for a single file (that doesn't have a file group).
    */
    static let fileGroupUUIDKey = "fileGroupUUID"
    // Not all files have to be associated with a file group.
    var fileGroupUUID:String?
    
    static let statusKey = "status"
    var status:DeferredUploadStatus!
    
    subscript(key:String) -> Any? {
        set {
            switch key {
            case DeferredUpload.deferredUploadIdKey:
                deferredUploadId = newValue as? Int64

            case DeferredUpload.sharingGroupUUIDKey:
                sharingGroupUUID = newValue as? String

            case DeferredUpload.userIdKey:
                userId = newValue as? UserId
                
            case DeferredUpload.fileGroupUUIDKey:
                fileGroupUUID = newValue as? String

            case DeferredUpload.statusKey:
                status = newValue as? DeferredUploadStatus
                
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
                    return DeferredUploadStatus(rawValue: rawValue)
                }
            
            default:
                return nil
        }
    }
}

class DeferredUploadRepository : Repository, RepositoryLookup, ModelIndexId {
    static let indexIdKey = DeferredUpload.deferredUploadIdKey
    
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

            "userId BIGINT NOT NULL, " +

            // Not NON NULL because this will be nil initially, and then get updated when the deferred uploaded is completed.
            "completionDate DATETIME," +

            "fileGroupUUID VARCHAR(\(Database.uuidLength)), " +

            "status VARCHAR(\(DeferredUploadStatus.maxCharacterLength)) NOT NULL, " +

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
        case fileGroupUUIDWithStatus(fileGroupUUID: String, status: DeferredUploadStatus)
        case resultsUUID(String)
        case userId(UserId)
        
        var description : String {
            switch self {
            case .deferredUploadId(let deferredUploadId):
                return "deferredUploadId(\(deferredUploadId))"
            case .fileGroupUUIDWithStatus(let fileGroupUUID, let status):
                return "fileGroupUUID(\(fileGroupUUID); status: \(status.rawValue))"
            case .resultsUUID(let resultsUUID):
                return "resultsUUID(\(resultsUUID))"
            case .userId(let userId):
                return "userId(\(userId))"
            }
        }
    }
    
    func lookupConstraint(key:LookupKey) -> String {
        switch key {
        case .deferredUploadId(let deferredUploadId):
            return "deferredUploadId = '\(deferredUploadId)'"
        case .fileGroupUUIDWithStatus(let fileGroupUUID, let status):
            return "fileGroupUUID = '\(fileGroupUUID)' and status = '\(status.rawValue)'"
        case .resultsUUID(let resultsUUID):
            return "resultsUUID = '\(resultsUUID)'"
        case .userId(let userId):
            return "userId = \(userId)"
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
    
    // deferredUploadId in the model is ignored and the automatically generated deferredUploadId is returned if the add is successful. Adds a new UUID for resultsUUID.
    func add(_ deferredUpload:DeferredUpload) -> AddResult {
        let insert = Database.PreparedStatement(repo: self, type: .insert)
        
        guard let userId = deferredUpload.userId else {
            return .otherError("No userId given")
        }
        
        insert.add(fieldName: DeferredUpload.sharingGroupUUIDKey, value: .stringOptional(deferredUpload.sharingGroupUUID))
        insert.add(fieldName: DeferredUpload.fileGroupUUIDKey, value: .stringOptional(deferredUpload.fileGroupUUID))
        insert.add(fieldName: DeferredUpload.statusKey, value: .stringOptional(deferredUpload.status?.rawValue))
        insert.add(fieldName: DeferredUpload.userIdKey, value: .int64(userId))

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
    // This `select` is not constrained by `UserId` because it is used from the `Uploader`, and the intent there is that the Uploader works *across* users.
    func select(rowsWithStatus status: [DeferredUploadStatus]) -> [DeferredUpload]? {
        let quotedStatusString = status.map {$0.rawValue}.map {"'\($0)'"}.joined(separator: ",")
        
        let query = "select * from \(tableName) where \(DeferredUpload.statusKey) IN (\(quotedStatusString))"

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

