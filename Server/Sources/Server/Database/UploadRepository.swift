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
case toPurge
}

class Upload : NSObject, Model {
    var uploadId: Int64!
    var fileUUID: String!
    var userId: Int64!
    var deviceUUID: String!
    var cloudFileName: String!
    var mimeType: String!
    var appMetaData: String!
    
    let fileUploadKey = "fileUpload"
    var fileUpload:Bool!
    
    var fileVersion: Int32!
    
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
    private static let tableName = "Upload"
    
    // See http://stackoverflow.com/questions/13397038/uuid-max-character-length
    static let uuidLength = 36
    
    static let maxFilenameLength = 256
    static let maxMimeTypeLength = 100
    static let stateMaxLength = 20

    static func create() -> Database.TableCreationResult {        
        let createColumns =
            "(uploadId BIGINT NOT NULL AUTO_INCREMENT, " +
            
            // Together, these three form a unique key. The deviceUUID is needed because two devices using the same userId (i.e., the same owning user credentials) could be uploading the same file at the same time.
        
            // permanent reference to file (assigned by app)
            "fileUUID VARCHAR(\(uuidLength)) NOT NULL, " +
        
            // reference into User table
            "userId BIGINT NOT NULL, " +
            
            // identifies a specific mobile device (assigned by app)
            "deviceUUID VARCHAR(\(uuidLength)) NOT NULL, " +
        
            // name of the file in cloud storage excluding the folder path.
            "cloudFileName VARCHAR(\(maxFilenameLength)) NOT NULL, " +
            
            // MIME type of the file
            "mimeType VARCHAR(\(maxMimeTypeLength)) NOT NULL, " +

            // Free-form JSON Structure; App-specific meta data
            "appMetaData TEXT, " +

            // true if file-upload, false if upload-deletion.
            "fileUpload BOOL NOT NULL, " +
            
            "fileVersion INT NOT NULL, " +
            "state VARCHAR(\(stateMaxLength)) NOT NULL, " +

            "fileSizeBytes BIGINT NOT NULL, " +

            "UNIQUE (fileUUID, userId, deviceUUID), " +
            "UNIQUE (uploadId))"
        
        return Database.session.createTableIfNeeded(tableName: "\(tableName)", columnCreateQuery: createColumns)
    }
    
    // Remove entire table.
    static func remove() -> Bool {
        return Database.session.connection.query(statement: "DROP TABLE \(tableName)")
    }
    
    // uploadId in the model is ignored and the automatically generated uploadId is returned if the add is successful.
    static func add(upload:Upload) -> Int64? {
        if upload.fileUUID == nil || upload.userId == nil || upload.deviceUUID == nil || upload.cloudFileName == nil || upload.mimeType == nil || upload.fileUpload == nil || upload.fileVersion == nil || upload.state == nil || upload.fileSizeBytes == nil {
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
        
        let query = "INSERT INTO \(tableName) (fileUUID, userId, deviceUUID, cloudFileName, mimeType, \(appMetaDataFieldName) fileUpload, fileVersion, state, fileSizeBytes) VALUES('\(upload.fileUUID!)', \(upload.userId!), '\(upload.deviceUUID!)', '\(upload.cloudFileName!)', '\(upload.mimeType!)' \(appMetaDataFieldValue), \(fileUploadValue), \(upload.fileVersion!), '\(upload.state!.rawValue)', \(upload.fileSizeBytes!));"
        
        if Database.session.connection.query(statement: query) {
            return Database.session.connection.lastInsertId()
        }
        else {
            let error = Database.session.error
            Log.error(message: "Could not add Upload: \(error)")
            return nil
        }
    }
    
    enum LookupResult {
        case found(Upload)
        case noUploadFound
        case error(String)
    }
    
    enum LookupKey : CustomStringConvertible {
        case uploadId(Int64)
        
        var description : String {
            switch self {
            case .uploadId(let uploadId):
                return "uploadId(\(uploadId))"
            }
        }
    }
    
    private static func lookupConstraint(key:LookupKey) -> String {
        switch key {
        case .uploadId(let uploadId):
            return "uploadId = '\(uploadId)'"
        }
    }
    
    static func lookup(key: LookupKey) -> LookupResult {
        let query = "select * from \(tableName) where " + lookupConstraint(key: key)
        let select = Select(query: query, modelInit: Upload.init, ignoreErrors:false)
        
        switch select.numberResultRows() {
        case 0:
            return .noUploadFound
            
        case 1:
            var result:Upload!
            select.forEachRow { rowModel in
                result = rowModel as! Upload
            }
            
            if select.forEachRowStatus != nil {
                let error = "Error: \(select.forEachRowStatus!) in Select forEachRow"
                Log.error(message: error)
                return .error(error)
            }
            
            return .found(result)

        default:
            let error = "Error: \(select.numberResultRows()) in Select result: More than one Upload found!"
            Log.error(message: error)
            return .error(error)
        }
    }
}
