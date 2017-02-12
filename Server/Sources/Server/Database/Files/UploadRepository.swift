//
//  UploadRepository.swift
//  Server
//
//  Created by Christopher Prince on 1/16/17.
//
//

// Persistent Storage for temporarily storing meta data for file uploads and file deletions before finally storing that info in the FileIndex. This also represents files that need to be purged from cloud storage-- this will be for losers of FileIndex update races and for upload deletions.

import Foundation
import PerfectLib

/*
    var uploadsSchema = new Schema({
        // _id: (ObjectId), // Uniquely identifies the upload (autocreated by Mongo)
        
        // Together, these three form a unique key. The deviceId is needed because two devices using the same userId (i.e., the same owning user credentials) could be uploading the same file at the same time.
		fileId: String, // UUID; permanent reference to file, assigned by app
		userId: ObjectId, // reference into PSUserCredentials (i.e., _id from PSUserCredentials)
        deviceId: String, // UUID; identifies a specific mobile device (assigned by app)

        cloudFileName: String, // name of the file in cloud storage excluding the folder path.

        mimeType: String, // MIME type of the file
        appMetaData: Schema.Types.Mixed, // Free-form JSON Structure; App-specific meta data
        
        fileUpload: Boolean, // true if file-upload, false if upload-deletion.
        
        fileVersion: {
          type: Number,
          min:  0,
          validate: {
            validator: Number.isInteger,
            message: '{VALUE} is not an integer value'
          }
        },
        
        state: {
          type: Number,
          min:  0,
          max: exports.maxStateValue,
          validate: {
            validator: Number.isInteger,
            message: '{VALUE} is not an integer value'
          }
        },
        
        fileSizeBytes: {
          type: Number,
          min:  0,
          validate: {
            validator: Number.isInteger,
            message: '{VALUE} is not an integer value'
          }
        }
        
    }, { collection: collectionName });
*/

enum UploadState : String {
case uploading
case uploaded
}

class Upload : NSObject, Model, Filenaming {
    var uploadId: Int64!
    var fileUUID: String!
    var userId: UserId!
    var deviceUUID: String!
    var mimeType: String!
    var appMetaData: String!
    
    let fileUploadKey = "fileUpload"
    var fileUpload:Bool!
    
    var fileVersion: FileVersionInt!
    
    let stateKey = "state"
    var state:UploadState!
    
    // Making this optional to give flexibility about when we create the Upload entry in the repo (e.g., before or after the upload to cloud storage).
    var fileSizeBytes: Int64?
    
    func typeConvertersToModel(propertyName:String) -> ((_ propertyValue:Any) -> Any?)? {
        switch propertyName {
            case stateKey:
                return {(x:Any) -> Any? in
                    return UploadState(rawValue: x as! String)
                }
            
            case fileUploadKey:
                return {(x:Any) -> Any? in
                    return (x as! Int8) == 1
                }
            
            default:
                return nil
        }
    }
}

class UploadRepository : Repository {
    private(set) var db:Database!

    init(_ db:Database) {
        self.db = db
    }
    
    var tableName:String {
        return "Upload"
    }
    
    let stateMaxLength = 20

    func create() -> Database.TableCreationResult {
        let createColumns =
            "(uploadId BIGINT NOT NULL AUTO_INCREMENT, " +
            
            // Together, these three form a unique key. The deviceUUID is needed because two devices using the same userId (i.e., the same owning user credentials) could be uploading the same file at the same time.
        
            // permanent reference to file (assigned by app)
            "fileUUID VARCHAR(\(Database.uuidLength)) NOT NULL, " +
        
            // reference into User table
            "userId BIGINT NOT NULL, " +
            
            // identifies a specific mobile device (assigned by app)
            "deviceUUID VARCHAR(\(Database.uuidLength)) NOT NULL, " +
                
            // MIME type of the file
            "mimeType VARCHAR(\(Database.maxMimeTypeLength)) NOT NULL, " +

            // App-specific meta data
            "appMetaData TEXT, " +

            // true if file-upload, false if upload-deletion.
            "fileUpload BOOL NOT NULL, " +
            
            "fileVersion INT NOT NULL, " +
            "state VARCHAR(\(stateMaxLength)) NOT NULL, " +

            // Can be null if we create the Upload entry before actually uploading the file.
            "fileSizeBytes BIGINT, " +

            "UNIQUE (fileUUID, userId, deviceUUID), " +
            "UNIQUE (uploadId))"
        
        return db.createTableIfNeeded(tableName: "\(tableName)", columnCreateQuery: createColumns)
    }
    
    private func haveNilField(upload:Upload) -> Bool {
        return upload.fileUUID == nil || upload.userId == nil || upload.deviceUUID == nil || upload.mimeType == nil || upload.fileUpload == nil || upload.fileVersion == nil || upload.state == nil
    }
    
    // uploadId in the model is ignored and the automatically generated uploadId is returned if the add is successful.
    func add(upload:Upload) -> Int64? {
        if haveNilField(upload: upload) {
            Log.error(message: "One of the model values was nil!")
            return nil
        }
    
        var appMetaDataFieldName = ""
        var appMetaDataFieldValue = ""
        if upload.appMetaData != nil {
            appMetaDataFieldName = " appMetaData, "
            
            // TODO: *2* Seems like we could use an encoding here to deal with sql injection issues.
            appMetaDataFieldValue = ", '\(upload.appMetaData!)'"
        }
        
        var fileSizeFieldName = ""
        var fileSizeFieldValue = ""
        if upload.fileSizeBytes != nil {
            fileSizeFieldName = ", fileSizeBytes"
            fileSizeFieldValue = ", \(upload.fileSizeBytes!)"
        }
        
        let fileUploadValue = upload.fileUpload == true ? 1 : 0
        
        let query = "INSERT INTO \(tableName) (fileUUID, userId, deviceUUID, mimeType, \(appMetaDataFieldName) fileUpload, fileVersion, state \(fileSizeFieldName)) VALUES('\(upload.fileUUID!)', \(upload.userId!), '\(upload.deviceUUID!)', '\(upload.mimeType!)' \(appMetaDataFieldValue), \(fileUploadValue), \(upload.fileVersion!), '\(upload.state!.rawValue)' \(fileSizeFieldValue));"
        
        if db.connection.query(statement: query) {
            return db.connection.lastInsertId()
        }
        else {
            let error = db.error
            Log.error(message: "Could not insert into \(tableName): \(error)")
            return nil
        }
    }
    
    // The Upload model *must* have an uploadId
    func update(upload:Upload) -> Bool {
        if upload.uploadId == nil || haveNilField(upload: upload) {
            Log.error(message: "One of the model values was nil!")
            return false
        }
    
        var appMetaDataField = ""
        if upload.appMetaData != nil {
            // TODO: *2* Seems like we could use an encoding here to deal with sql injection issues.
            appMetaDataField = ", appMetaData='\(upload.appMetaData!)'"
        }
        
        var fileSizeBytesField = ""
        if upload.fileSizeBytes != nil {
            fileSizeBytesField = ", fileSizeBytes=\(upload.fileSizeBytes!)"
        }
        
        let fileUploadValue = upload.fileUpload == true ? 1 : 0
        
        let query = "UPDATE \(tableName) SET fileUUID='\(upload.fileUUID!)', userId=\(upload.userId!), deviceUUID='\(upload.deviceUUID!)', mimeType='\(upload.mimeType!)', fileUpload=\(fileUploadValue), fileVersion=\(upload.fileVersion!), state='\(upload.state!.rawValue)' \(fileSizeBytesField) \(appMetaDataField) WHERE uploadId=\(upload.uploadId!)"
        
        if db.connection.query(statement: query) {
            // "When using UPDATE, MySQL will not update columns where the new value is the same as the old value. This creates the possibility that mysql_affected_rows may not actually equal the number of rows matched, only the number of rows that were literally affected by the query." From: https://dev.mysql.com/doc/apis-php/en/apis-php-function.mysql-affected-rows.html
            if db.connection.numberAffectedRows() <= 1 {
                return true
            }
            else {
                Log.error(message: "Did not have <= 1 row updated: \(db.connection.numberAffectedRows())")
                return false
            }
        }
        else {
            let error = db.error
            Log.error(message: "Could not update \(tableName): \(error)")
            return false
        }
    }
    
    enum LookupKey : CustomStringConvertible {
        case uploadId(Int64)
        case fileUUID(String)
        case userId(UserId)
        case filesForUserDevice(userId:UserId, deviceUUID:String)
        
        var description : String {
            switch self {
            case .uploadId(let uploadId):
                return "uploadId(\(uploadId))"
            case .fileUUID(let fileUUID):
                return "fileUUID(\(fileUUID))"
            case .userId(let userId):
                return "userId(\(userId))"
            case .filesForUserDevice(let userId, let deviceUUID):
                return "userId(\(userId)); deviceUUID(\(deviceUUID)); "
            }
        }
    }
    
    func lookupConstraint(key:LookupKey) -> String {
        switch key {
        case .uploadId(let uploadId):
            return "uploadId = '\(uploadId)'"
        case .fileUUID(let fileUUID):
            return "fileUUID = '\(fileUUID)'"
        case .userId(let userId):
            return "userId = '\(userId)'"
        case .filesForUserDevice(let userId, let deviceUUID):
            return "userId = \(userId) and deviceUUID = '\(deviceUUID)'"
        }
    }
    
    func select(forUserId userId: UserId, deviceUUID:String, andState state:UploadState) -> Select {
        let query = "select * from \(tableName) where userId=\(userId) and deviceUUID='\(deviceUUID)' and state='\(state.rawValue)'"
        return Select(db:db, query: query, modelInit: Upload.init, ignoreErrors:false)
    }
}
