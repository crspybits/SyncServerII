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
case toDeleteFromFileIndex

static func maxCharacterLength() -> Int { return 22 }
}

class Upload : NSObject, Model, Filenaming {
    var uploadId: Int64!
    var fileUUID: String!
    var userId: UserId!
    var fileVersion: FileVersionInt!
    var deviceUUID: String!
    
    // TODO: *0*
    // var creationDate:Date!
    
    let stateKey = "state"
    var state:UploadState!
    
    var appMetaData: String?
    
    // Making this optional to give flexibility about when we create the Upload entry in the repo (e.g., before or after the upload to cloud storage).
    var fileSizeBytes: Int64?
    
    // These two are not present in upload deletions.
    var mimeType: String?
    var cloudFolderName: String?

    func typeConvertersToModel(propertyName:String) -> ((_ propertyValue:Any) -> Any?)? {
        switch propertyName {
            case stateKey:
                return {(x:Any) -> Any? in
                    return UploadState(rawValue: x as! String)
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
                
            // MIME type of the file; will be nil for UploadDeletion's.
            "mimeType VARCHAR(\(Database.maxMimeTypeLength)), " +
            
            // Cloud folder name; will be nil for UploadDeletion's.
            "cloudFolderName VARCHAR(\(Database.maxCloudFolderNameLength)), " +

            // Optional app-specific meta data
            "appMetaData TEXT, " +
            
            "fileVersion INT NOT NULL, " +
            "state VARCHAR(\(UploadState.maxCharacterLength())) NOT NULL, " +

            // Can be null if we create the Upload entry before actually uploading the file.
            "fileSizeBytes BIGINT, " +

            "UNIQUE (fileUUID, userId, deviceUUID), " +
            "UNIQUE (uploadId))"
        
        return db.createTableIfNeeded(tableName: "\(tableName)", columnCreateQuery: createColumns)
    }
    
    private func haveNilField(upload:Upload) -> Bool {
        return upload.fileUUID == nil || upload.userId == nil || upload.fileVersion == nil || upload.state == nil
    }
    
    enum AddResult {
    case success(uploadId:Int64)
    case duplicateEntry
    case aModelValueWasNil
    case otherError(String)
    }
    
    // uploadId in the model is ignored and the automatically generated uploadId is returned if the add is successful.
    func add(upload:Upload) -> AddResult {
        if haveNilField(upload: upload) {
            Log.error(message: "One of the model values was nil!")
            return .aModelValueWasNil
        }
    
        // TODO: *2* Seems like we could use an encoding here to deal with sql injection issues.
        let (appMetaDataFieldValue, appMetaDataFieldName) = getInsertFieldValueAndName(fieldValue: upload.appMetaData, fieldName: "appMetaData")

        let (fileSizeFieldValue, fileSizeFieldName) = getInsertFieldValueAndName(fieldValue: upload.fileSizeBytes, fieldName: "fileSizeBytes", fieldIsString:false)
 
        let (mimeTypeFieldValue, mimeTypeFieldName) = getInsertFieldValueAndName(fieldValue: upload.mimeType, fieldName: "mimeType")
        
        let (cloudFolderNameFieldValue, cloudFolderNameFieldName) = getInsertFieldValueAndName(fieldValue: upload.cloudFolderName, fieldName: "cloudFolderName")
        
        let query = "INSERT INTO \(tableName) (fileUUID, userId, deviceUUID, fileVersion, state \(fileSizeFieldName) \(mimeTypeFieldName) \(appMetaDataFieldName) \(cloudFolderNameFieldName)) VALUES('\(upload.fileUUID!)', \(upload.userId!), '\(upload.deviceUUID!)', \(upload.fileVersion!), '\(upload.state!.rawValue)' \(fileSizeFieldValue) \(mimeTypeFieldValue) \(appMetaDataFieldValue) \(cloudFolderNameFieldValue));"
        
        if db.connection.query(statement: query) {
            return .success(uploadId: db.connection.lastInsertId())
        }
        else if db.connection.errorCode() == Database.duplicateEntryForKey {
            return .duplicateEntry
        }
        else {
            let error = db.error
            let message = "Could not insert into \(tableName): \(error)"
            Log.error(message: message)
            return .otherError(message)
        }
    }
    
    // The Upload model *must* have an uploadId
    func update(upload:Upload) -> Bool {
        if upload.uploadId == nil || haveNilField(upload: upload) {
            Log.error(message: "One of the model values was nil!")
            return false
        }
    
        // TODO: *2* Seems like we could use an encoding here to deal with sql injection issues.
        let appMetaDataField = getUpdateFieldSetter(fieldValue: upload.appMetaData, fieldName: "appMetaData")

        let fileSizeBytesField = getUpdateFieldSetter(fieldValue: upload.fileSizeBytes, fieldName: "fileSizeBytes", fieldIsString: false)
        
        let mimeTypeField = getUpdateFieldSetter(fieldValue: upload.mimeType, fieldName: "mimeType")
        
        let cloudFolderNameField = getUpdateFieldSetter(fieldValue: upload.cloudFolderName, fieldName: "cloudFolderName")
        
        let query = "UPDATE \(tableName) SET fileUUID='\(upload.fileUUID!)', userId=\(upload.userId!), fileVersion=\(upload.fileVersion!), state='\(upload.state!.rawValue)', deviceUUID='\(upload.deviceUUID!)' \(fileSizeBytesField) \(appMetaDataField) \(mimeTypeField) \(cloudFolderNameField) WHERE uploadId=\(upload.uploadId!)"
        
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
        case primaryKey(fileUUID:String, userId:UserId, deviceUUID:String)
        
        var description : String {
            switch self {
            case .uploadId(let uploadId):
                return "uploadId(\(uploadId))"
            case .fileUUID(let fileUUID):
                return "fileUUID(\(fileUUID))"
            case .userId(let userId):
                return "userId(\(userId))"
            case .filesForUserDevice(let userId, let deviceUUID):
                return "userId(\(userId)); deviceUUID(\(deviceUUID))"
            case .primaryKey(let fileUUID, let userId, let deviceUUID):
                return "fileUUID(\(fileUUID)); userId(\(userId)); deviceUUID(\(deviceUUID))"
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
        case .primaryKey(let fileUUID, let userId, let deviceUUID):
            return "fileUUID = '\(fileUUID)' and userId = \(userId) and deviceUUID = '\(deviceUUID)'"
        }
    }
    
    func select(forUserId userId: UserId, deviceUUID:String, andState state:UploadState? = nil) -> Select {
    
        var query = "select * from \(tableName) where userId=\(userId) and deviceUUID='\(deviceUUID)'"
        
        if state != nil {
            query += " and state='\(state!.rawValue)'"
        }
        
        return Select(db:db, query: query, modelInit: Upload.init, ignoreErrors:false)
    }
    
    enum UploadedFilesResult {
    case uploads([FileInfo])
    case error(Swift.Error)
    }
    
    // With nil `andState` parameter value, returns both file uploads and upload deletions.
    func uploadedFiles(forUserId userId: UserId, deviceUUID: String, andState state:UploadState? = nil) -> UploadedFilesResult {
        let selectUploadedFiles = select(forUserId: userId, deviceUUID: deviceUUID, andState: state)

        var fileInfoResult:[FileInfo] = []
        
        selectUploadedFiles.forEachRow { rowModel in
            let rowModel = rowModel as! Upload

            let fileInfo = FileInfo()!
            fileInfo.fileUUID = rowModel.fileUUID
            fileInfo.appMetaData = rowModel.appMetaData
            fileInfo.fileVersion = rowModel.fileVersion
            fileInfo.deleted = rowModel.state == .toDeleteFromFileIndex
            fileInfo.fileSizeBytes = rowModel.fileSizeBytes
            fileInfo.mimeType = rowModel.mimeType
            fileInfo.cloudFolderName = rowModel.cloudFolderName
            
            fileInfoResult.append(fileInfo)
        }
        
        if selectUploadedFiles.forEachRowStatus == nil {
            return .uploads(fileInfoResult)
        }
        else {
            return .error(selectUploadedFiles.forEachRowStatus!)
        }
    }
}
