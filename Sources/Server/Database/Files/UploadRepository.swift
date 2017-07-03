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
import SyncServerShared

enum UploadState : String {
case uploading
case uploaded
case toDeleteFromFileIndex

static func maxCharacterLength() -> Int { return 22 }
}

class Upload : NSObject, Model, Filenaming {
    static let uploadIdKey = "uploadId"
    var uploadId: Int64!
    
    static let fileUUIDKey = "fileUUID"
    var fileUUID: String!
    
    static let userIdKey = "userId"
    // The userId of the sharing or owning user, i.e., this is not the owning user id.
    var userId: UserId!
    
    static let fileVersionKey = "fileVersion"
    var fileVersion: FileVersionInt!
    
    static let deviceUUIDKey = "deviceUUID"
    var deviceUUID: String!
    
    // The following two dates are required for file uploads.
    static let creationDateKey = "creationDate"
    var creationDate:Date?
    
    // Mostly for future use since we're not yet allowing multiple file versions.
    static let updateDateKey = "updateDate"
    var updateDate:Date?
    
    static let stateKey = "state"
    var state:UploadState!
    
    static let appMetaDataKey = "appMetaData"
    var appMetaData: String?
    
    static let fileSizeBytesKey = "fileSizeBytes"
    
    // Required only when the state is .uploaded
    var fileSizeBytes: Int64?
    
    // These two are not present in upload deletions.
    static let mimeTypeKey = "mimeType"
    var mimeType: String?
    static let cloudFolderNameKey = "cloudFolderName"
    var cloudFolderName: String?
    
    subscript(key:String) -> Any? {
        set {
            switch key {
            case Upload.uploadIdKey:
                uploadId = newValue as! Int64?

            case Upload.fileUUIDKey:
                fileUUID = newValue as! String?

            case Upload.userIdKey:
                userId = newValue as! UserId?
                
            case Upload.fileVersionKey:
                fileVersion = newValue as! FileVersionInt?
                
            case Upload.deviceUUIDKey:
                deviceUUID = newValue as! String?
                
            case Upload.creationDateKey:
                creationDate = newValue as! Date?

            case Upload.updateDateKey:
                updateDate = newValue as! Date?

            case Upload.stateKey:
                state = newValue as! UploadState?
                
            case Upload.appMetaDataKey:
                appMetaData = newValue as! String?
            
            case Upload.fileSizeBytesKey:
                fileSizeBytes = newValue as! Int64?
                
            case Upload.mimeTypeKey:
                mimeType = newValue as! String?
                
            case Upload.cloudFolderNameKey:
                cloudFolderName = newValue as! String?

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
            case Upload.stateKey:
                return {(x:Any) -> Any? in
                    return UploadState(rawValue: x as! String)
                }
            
            case Upload.creationDateKey:
                return {(x:Any) -> Any? in
                    return DateExtras.date(x as! String, fromFormat: .DATETIME)
                }

            case Upload.updateDateKey:
                return {(x:Any) -> Any? in
                    return DateExtras.date(x as! String, fromFormat: .DATETIME)
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
    
    func upcreate() -> Database.TableUpcreateResult {
        let createColumns =
            "(uploadId BIGINT NOT NULL AUTO_INCREMENT, " +
            
            // Together, the next three fields form a unique key. The deviceUUID is needed because two devices using the same userId (i.e., the same owning user credentials) could be uploading the same file at the same time.
        
            // permanent reference to file (assigned by app)
            "fileUUID VARCHAR(\(Database.uuidLength)) NOT NULL, " +
        
            // reference into User table
            "userId BIGINT NOT NULL, " +
                
            // identifies a specific mobile device (assigned by app)
            "deviceUUID VARCHAR(\(Database.uuidLength)) NOT NULL, " +
            
            // Not saying "NOT NULL" here only because in the first deployed version of the database, I didn't have these dates. Plus, upload deletions need not have dates.
            "creationDate DATETIME," +
            "updateDate DATETIME," +
                
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
        
        let result = db.createTableIfNeeded(tableName: "\(tableName)", columnCreateQuery: createColumns)
        switch result {
        case .success(.alreadyPresent):
            // Table was already there. Do we need to update it?
            // Evolution 1: Are creationDate and updateDate present? If not, add them.
            if db.columnExists(Upload.creationDateKey, in: tableName) == false {
                if !db.addColumn("\(Upload.creationDateKey) DATETIME", to: tableName) {
                    return .failure(.columnCreation)
                }
            }
            if db.columnExists(Upload.updateDateKey, in: tableName) == false {
                if !db.addColumn("\(Upload.updateDateKey) DATETIME", to: tableName) {
                    return .failure(.columnCreation)
                }
            }
            break
            
        default:
            break
        }
        
        return result
    }
    
    private func haveNilField(upload:Upload) -> Bool {
        // Basic criteria-- applies across uploads and upload deletion.
        if upload.deviceUUID == nil || upload.fileUUID == nil || upload.userId == nil || upload.fileVersion == nil || upload.state == nil {
            return true
        }
        if upload.state == .toDeleteFromFileIndex {
            return false
        }
        
        // We're uploading a file if we get to here. Criteria only for file uploads:
        if upload.mimeType == nil || upload.cloudFolderName == nil || upload.creationDate == nil || upload.updateDate == nil {
            return true
        }
        if upload.state == .uploading {
            return false
        }
        
        // Have to have fileSizeBytes when we're in the uploaded state.
        return upload.fileSizeBytes == nil
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
        let (appMetaDataFieldValue, appMetaDataFieldName) = getInsertFieldValueAndName(fieldValue: upload.appMetaData, fieldName: Upload.appMetaDataKey)

        let (fileSizeFieldValue, fileSizeFieldName) = getInsertFieldValueAndName(fieldValue: upload.fileSizeBytes, fieldName: Upload.fileSizeBytesKey, fieldIsString:false)
 
        let (mimeTypeFieldValue, mimeTypeFieldName) = getInsertFieldValueAndName(fieldValue: upload.mimeType, fieldName: Upload.mimeTypeKey)
        
        let (cloudFolderNameFieldValue, cloudFolderNameFieldName) = getInsertFieldValueAndName(fieldValue: upload.cloudFolderName, fieldName: Upload.cloudFolderNameKey)
        
        var creationDateValue:String?
        var updateDateValue:String?
        
        if upload.creationDate != nil {
            creationDateValue = DateExtras.date(upload.creationDate!, toFormat: .DATETIME)
        }
        
        if upload.updateDate != nil {
            updateDateValue = DateExtras.date(upload.updateDate!, toFormat: .DATETIME)
        }
        
         let (creationDateFieldValue, creationDateFieldName) = getInsertFieldValueAndName(fieldValue: creationDateValue, fieldName: Upload.creationDateKey)
        
         let (updateDateFieldValue, updateDateFieldName) = getInsertFieldValueAndName(fieldValue: updateDateValue, fieldName: Upload.updateDateKey)
        
        let query = "INSERT INTO \(tableName) (\(Upload.fileUUIDKey), \(Upload.userIdKey), \(Upload.deviceUUIDKey), \(Upload.fileVersionKey), \(Upload.stateKey) \(creationDateFieldName) \(updateDateFieldName) \(fileSizeFieldName) \(mimeTypeFieldName) \(appMetaDataFieldName) \(cloudFolderNameFieldName)) VALUES('\(upload.fileUUID!)', \(upload.userId!), '\(upload.deviceUUID!)', \(upload.fileVersion!), '\(upload.state!.rawValue)' \(creationDateFieldValue) \(updateDateFieldValue) \(fileSizeFieldValue) \(mimeTypeFieldValue) \(appMetaDataFieldValue) \(cloudFolderNameFieldValue));"
        
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
            fileInfo.creationDate = rowModel.creationDate
            fileInfo.updateDate = rowModel.creationDate
            
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
