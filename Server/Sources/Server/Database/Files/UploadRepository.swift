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
case uploaded
case toPurge
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
    
    var fileSizeBytes: Int64!
    
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

            "fileSizeBytes BIGINT NOT NULL, " +

            "UNIQUE (fileUUID, userId, deviceUUID), " +
            "UNIQUE (uploadId))"
        
        return db.createTableIfNeeded(tableName: "\(tableName)", columnCreateQuery: createColumns)
    }
    
    // uploadId in the model is ignored and the automatically generated uploadId is returned if the add is successful.
    func add(upload:Upload) -> Int64? {
        if upload.fileUUID == nil || upload.userId == nil || upload.deviceUUID == nil || upload.mimeType == nil || upload.fileUpload == nil || upload.fileVersion == nil || upload.state == nil || upload.fileSizeBytes == nil {
            Log.error(message: "One of the model values was nil!")
            return nil
        }
    
        var appMetaDataFieldName = ""
        var appMetaDataFieldValue = ""
        if upload.appMetaData != nil {
            appMetaDataFieldName = " appMetaData, "
            
            // TODO: Seems like we could use an encoding here to deal with sql injection issues.
            appMetaDataFieldValue = ", '\(upload.appMetaData!)'"
        }
        
        let fileUploadValue = upload.fileUpload == true ? 1 : 0
        
        let query = "INSERT INTO \(tableName) (fileUUID, userId, deviceUUID, mimeType, \(appMetaDataFieldName) fileUpload, fileVersion, state, fileSizeBytes) VALUES('\(upload.fileUUID!)', \(upload.userId!), '\(upload.deviceUUID!)', '\(upload.mimeType!)' \(appMetaDataFieldValue), \(fileUploadValue), \(upload.fileVersion!), '\(upload.state!.rawValue)', \(upload.fileSizeBytes!));"
        
        if db.connection.query(statement: query) {
            return db.connection.lastInsertId()
        }
        else {
            let error = db.error
            Log.error(message: "Could not insert into \(tableName): \(error)")
            return nil
        }
    }
    
    enum LookupKey : CustomStringConvertible {
        case uploadId(Int64)
        case fileUUID(String)
        case userId(UserId)
        case filesForUser(userId:UserId, deviceUUID:String)
        
        var description : String {
            switch self {
            case .uploadId(let uploadId):
                return "uploadId(\(uploadId))"
            case .fileUUID(let fileUUID):
                return "fileUUID(\(fileUUID))"
            case .userId(let userId):
                return "userId(\(userId))"
            case .filesForUser(let userId, let deviceUUID):
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
        case .filesForUser(let userId, let deviceUUID):
            return "userId = \(userId) and deviceUUID = '\(deviceUUID)'"
        }
    }
    
    func selectForTransferToUpload(userId: UserId, deviceUUID:String) -> String {
        let filesForUserConstraint = lookupConstraint(key: .filesForUser(userId: userId, deviceUUID: deviceUUID))

        // The ordering of the fields in the following SELECT is *very important*. It must correspond to that used in the FileIndexRepository in the method that uses this method.
        // Also: false corresponds to the `deleted` field in the FileIndex.
        let select = "SELECT  fileUUID, userId, deviceUUID, mimeType, appMetaData, false, fileVersion, fileSizeBytes " +
            "FROM  \(tableName) " +
            "WHERE  \(filesForUserConstraint)"
        return select
    }
}
