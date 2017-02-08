//
//  FileIndexRepository.swift
//  Server
//
//  Created by Christopher Prince on 1/21/17.
//
//

// Meta data for files currently in cloud storage.

import Foundation
import PerfectLib

typealias FileIndexId = Int64

class FileIndex : NSObject, Model, Filenaming {
    var fileIndexId: FileIndexId!
    var fileUUID: String!
    var deviceUUID:String!
    var userId: UserId!
    var mimeType: String!
    var appMetaData: String!
    
    let deletedKey = "deleted"
    var deleted:Bool!
    
    var fileVersion: FileVersionInt!
    
    var fileSizeBytes: Int64!
    
    func typeConvertersToModel(propertyName:String) -> ((_ propertyValue:Any) -> Any?)? {
        switch propertyName {
            case deletedKey:
                return {(x:Any) -> Any? in
                    return (x as! Int8) == 1
                }
            
            default:
                return nil
        }
    }
}

class FileIndexRepository : Repository {
    private(set) var db:Database!
    
    init(_ db:Database) {
        self.db = db
    }
    
    var tableName:String {
        return "FileIndex"
    }
    
    func create() -> Database.TableCreationResult {
        let createColumns =
            "(fileIndexId BIGINT NOT NULL AUTO_INCREMENT, " +
                        
            // permanent reference to file (assigned by app)
            "fileUUID VARCHAR(\(Database.uuidLength)) NOT NULL, " +
        
            // reference into User table
            "userId BIGINT NOT NULL, " +
            
            // identifies a specific mobile device (assigned by app)
            // This plays a different role than it did in the Upload table. Here, it forms part of the filename in cloud storage, and thus must be retained. We will ignore this field otherwise, i.e., we will not have two entries in this table for the same userId, fileUUID pair.
            "deviceUUID VARCHAR(\(Database.uuidLength)) NOT NULL, " +
                
            // MIME type of the file
            "mimeType VARCHAR(\(Database.maxMimeTypeLength)) NOT NULL, " +

            // App-specific meta data
            "appMetaData TEXT, " +

            // true if file has been deleted, false if not.
            "deleted BOOL NOT NULL, " +
            
            "fileVersion INT NOT NULL, " +

            "fileSizeBytes BIGINT NOT NULL, " +

            "UNIQUE (fileUUID, userId), " +
            "UNIQUE (fileIndexId))"
        
        return db.createTableIfNeeded(tableName: "\(tableName)", columnCreateQuery: createColumns)
    }
    
    private func columnNames(appMetaDataFieldName:String = "appMetaData,") -> String {
        return "fileUUID, userId, deviceUUID, mimeType, \(appMetaDataFieldName) deleted, fileVersion, fileSizeBytes"
    }
    
    // uploadId in the model is ignored and the automatically generated uploadId is returned if the add is successful.
    func add(fileIndex:FileIndex) -> Int64? {
        if fileIndex.fileUUID == nil || fileIndex.userId == nil || fileIndex.mimeType == nil || fileIndex.deviceUUID == nil || fileIndex.deleted == nil || fileIndex.fileVersion == nil || fileIndex.fileSizeBytes == nil {
            Log.error(message: "One of the model values was nil!")
            return nil
        }
    
        var appMetaDataFieldValue = ""
        var columns = columnNames(appMetaDataFieldName: "")
        
        if fileIndex.appMetaData != nil {
            // TODO: Seems like we could use an encoding here to deal with sql injection issues.
            appMetaDataFieldValue = ", '\(fileIndex.appMetaData!)'"
            
            columns = columnNames()
        }
        
        let deletedValue = fileIndex.deleted == true ? 1 : 0
        
        let query = "INSERT INTO \(tableName) (\(columns)) VALUES('\(fileIndex.fileUUID!)', \(fileIndex.userId!), '\(fileIndex.deviceUUID!)', '\(fileIndex.mimeType!)' \(appMetaDataFieldValue), \(deletedValue), \(fileIndex.fileVersion!), \(fileIndex.fileSizeBytes!));"
        
        if db.connection.query(statement: query) {
            return db.connection.lastInsertId()
        }
        else {
            let error = db.error
            Log.error(message: "Could not insert row into \(tableName): \(error)")
            return nil
        }
    }
    
    enum LookupKey : CustomStringConvertible {
        case fileIndexId(Int64)
        case userId(UserId)
        case primaryKeys(userId:String, fileUUID:String)
        
        var description : String {
            switch self {
            case .fileIndexId(let fileIndexId):
                return "fileIndexId(\(fileIndexId))"
            case .userId(let userId):
                return "userId(\(userId))"
            case .primaryKeys(let userId, let fileUUID):
                return "userId(\(userId)); fileUUID(\(fileUUID))"
            }
        }
    }
    
    func lookupConstraint(key:LookupKey) -> String {
        switch key {
        case .fileIndexId(let fileIndexId):
            return "fileIndexId = '\(fileIndexId)'"
        case .userId(let userId):
            return "userId = '\(userId)'"
        case .primaryKeys(let userId, let fileUUID):
            return "userId = \(userId) and fileUUID = '\(fileUUID)'"
        }
    }
    
    // Returns nil on failure, and on success returns the number of uploads transferred.
    func transferUploads(userId: UserId, deviceUUID:String, upload:UploadRepository) -> Int32? {
        // The ordering of fields in the INSERT must match that in selectForTransferToUpload.
        let query = "INSERT INTO \(tableName) (\(columnNames())) " +
        upload.selectForTransferToUpload(userId: userId, deviceUUID: deviceUUID)
        
        if db.connection.query(statement: query) {
            return Int32(db.connection.numberAffectedRows())
        }
        else {
            let error = db.error
            Log.error(message: "Could not transferUploads: \(error)")
            return nil
        }
    }
    
    enum FileIndexResult {
    case fileIndex([FileInfo])
    case error(Swift.Error)
    }
    
    func fileIndex(forUserId userId: UserId) -> FileIndexResult {
        let query = "select * from \(tableName) where userId = \(userId)"
        let select = Select(db:db, query: query, modelInit: FileIndex.init, ignoreErrors:false)
        
        var result:[FileInfo] = []
        
        select.forEachRow { rowModel in
            let rowModel = rowModel as! FileIndex

            let fileInfo = FileInfo()!
            fileInfo.fileUUID = rowModel.fileUUID
            fileInfo.appMetaData = rowModel.appMetaData
            fileInfo.fileVersion = rowModel.fileVersion
            fileInfo.deleted = rowModel.deleted
            fileInfo.fileSizeBytes = rowModel.fileSizeBytes
            fileInfo.mimeType = rowModel.mimeType
            
            result.append(fileInfo)
        }
        
        if select.forEachRowStatus == nil {
            return .fileIndex(result)
        }
        else {
            return .error(select.forEachRowStatus!)
        }
    }
}
