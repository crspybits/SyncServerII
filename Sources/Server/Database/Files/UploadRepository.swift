//
//  UploadRepository.swift
//  Server
//
//  Created by Christopher Prince on 1/16/17.
//
//

// Persistent Storage for temporarily storing meta data for file uploads and file deletions before finally storing that info in the FileIndex. This also represents files that need to be purged from cloud storage-- this will be for losers of FileIndex update races and for upload deletions.

import Foundation
import SyncServerShared
import LoggerAPI

enum UploadState : String {
case uploadingFile
case uploadedFile
case uploadingUndelete
case uploadedUndelete
case uploadingAppMetaData
case toDeleteFromFileIndex

static func maxCharacterLength() -> Int { return 22 }
}

class Upload : NSObject, Model, Filenaming {
    static let uploadIdKey = "uploadId"
    var uploadId: Int64!
    
    static let fileUUIDKey = "fileUUID"
    var fileUUID: String!
    
    static let userIdKey = "userId"
    // The userId of the uploading user. i.e., this is not necessarily the owning user id.
    var userId: UserId!
    
    // 3/15/18-- Can now be nil-- when we do an upload app meta data. Keeping it as `!` so it abides by the FileNaming protocol.
    static let fileVersionKey = "fileVersion"
    var fileVersion: FileVersionInt!
    
    static let deviceUUIDKey = "deviceUUID"
    var deviceUUID: String!
    
    static let fileGroupUUIDKey = "fileGroupUUID"
    // Not all files have to be associated with a file group.
    var fileGroupUUID:String?
    
    // Currently allowing files to be in exactly one sharing group.
    static let sharingGroupUUIDKey = "sharingGroupUUID"
    var sharingGroupUUID: String!
    
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

    static let appMetaDataVersionKey = "appMetaDataVersion"
    var appMetaDataVersion: AppMetaDataVersionInt?
    
    static let fileSizeBytesKey = "fileSizeBytes"
    
    // Required only when the state is .uploaded
    var fileSizeBytes: Int64?
    
    // This is not present in upload deletions.
    static let mimeTypeKey = "mimeType"
    var mimeType: String?
    
    subscript(key:String) -> Any? {
        set {
            switch key {
            case Upload.uploadIdKey:
                uploadId = newValue as! Int64?

            case Upload.fileUUIDKey:
                fileUUID = newValue as! String?
                
            case Upload.fileGroupUUIDKey:
                fileGroupUUID = newValue as! String?

            case Upload.sharingGroupUUIDKey:
                sharingGroupUUID = newValue as! String?

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
                
            case Upload.appMetaDataVersionKey:
                appMetaDataVersion = newValue as! AppMetaDataVersionInt?
            
            case Upload.fileSizeBytesKey:
                fileSizeBytes = newValue as! Int64?
                
            case Upload.mimeTypeKey:
                mimeType = newValue as! String?

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

class UploadRepository : Repository, RepositoryLookup {
    private(set) var db:Database!

    required init(_ db:Database) {
        self.db = db
    }
    
    var tableName:String {
        return UploadRepository.tableName
    }
    
    static var tableName:String {
        return "Upload"
    }
    
    func upcreate() -> Database.TableUpcreateResult {
        let createColumns =
            "(uploadId BIGINT NOT NULL AUTO_INCREMENT, " +
            
            // Together, the next three fields form a unique key. The deviceUUID is needed because two devices using the same userId (i.e., the same owning user credentials) could be uploading the same file at the same time.
        
            // permanent reference to file (assigned by app)
            "fileUUID VARCHAR(\(Database.uuidLength)) NOT NULL, " +
        
            // reference into User table
            // TODO: *2* Make this a foreign reference.
            "userId BIGINT NOT NULL, " +
                
            // identifies a specific mobile device (assigned by app)
            "deviceUUID VARCHAR(\(Database.uuidLength)) NOT NULL, " +
            
            // identifies a group of files (assigned by app)
            "fileGroupUUID VARCHAR(\(Database.uuidLength)), " +
            
            "sharingGroupUUID VARCHAR(\(Database.uuidLength)) NOT NULL, " +
            
            // Not saying "NOT NULL" here only because in the first deployed version of the database, I didn't have these dates. Plus, upload deletions need not have dates. And when uploading a new version of a file we won't give the creationDate.
            "creationDate DATETIME," +
            "updateDate DATETIME," +
                
            // MIME type of the file; will be nil for UploadDeletion's.
            "mimeType VARCHAR(\(Database.maxMimeTypeLength)), " +

            // Optional app-specific meta data
            "appMetaData TEXT, " +
            
            // 3/25/18; This used to be `NOT NULL` but now allowing it to be NULL because when we upload an app meta data change, it will be null.
            "fileVersion INT, " +
            
            // Making this optional because appMetaData is optional. If there is app meta data, this must not be null.
            "appMetaDataVersion INT, " +
            
            "state VARCHAR(\(UploadState.maxCharacterLength())) NOT NULL, " +

            // Can be null if we create the Upload entry before actually uploading the file.
            "fileSizeBytes BIGINT, " +
            
            "FOREIGN KEY (sharingGroupUUID) REFERENCES \(SharingGroupRepository.tableName)(\(SharingGroup.sharingGroupUUIDKey)), " +

            // Not including fileVersion in the key because I don't want to allow the possiblity of uploading vN of a file and vM of a file at the same time.
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

            // 2/25/18; Evolution 2: Remove the cloudFolderName column
            let cloudFolderNameKey = "cloudFolderName"
            if db.columnExists(cloudFolderNameKey, in: tableName) == true {
                if !db.removeColumn(cloudFolderNameKey, from: tableName) {
                    return .failure(.columnRemoval)
                }
            }
            
            // 3/23/18; Evolution 3: Add the appMetaDataVersion column.
            if db.columnExists(Upload.appMetaDataVersionKey, in: tableName) == false {
                if !db.addColumn("\(Upload.appMetaDataVersionKey) INT", to: tableName) {
                    return .failure(.columnCreation)
                }
            }
            
            if db.columnExists(Upload.fileGroupUUIDKey, in: tableName) == false {
                if !db.addColumn("\(Upload.fileGroupUUIDKey) VARCHAR(\(Database.uuidLength))", to: tableName) {
                    return .failure(.columnCreation)
                }
            }
            
        default:
            break
        }
        
        return result
    }
    
    private func haveNilField(upload:Upload, fileInFileIndex: Bool) -> Bool {
        // Basic criteria-- applies across uploads and upload deletion.
        if upload.deviceUUID == nil || upload.fileUUID == nil || upload.userId == nil || upload.state == nil || upload.sharingGroupUUID == nil {
            return true
        }
        
        if upload.fileVersion == nil && upload.state != .uploadingAppMetaData  {
            return true
        }
        
        if upload.state == .toDeleteFromFileIndex {
            return false
        }
        
        if upload.state == .uploadingAppMetaData {
            return upload.appMetaData == nil || upload.appMetaDataVersion == nil
        }
        
        // We're uploading a file if we get to here. Criteria only for file uploads:
        if upload.mimeType == nil || upload.updateDate == nil {
            return true
        }
        
        // The meta data and version must be nil or non-nil *together*.
        let metaDataNil = upload.appMetaData == nil
        let metaDataVersionNil = upload.appMetaDataVersion == nil
        if metaDataNil != metaDataVersionNil {
            return true
        }
        
        if !fileInFileIndex && upload.creationDate == nil {
            return true
        }
        
        if upload.state == .uploadingFile || upload.state == .uploadingUndelete {
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
    func add(upload:Upload, fileInFileIndex:Bool=false) -> AddResult {
        if haveNilField(upload: upload, fileInFileIndex:fileInFileIndex) {
            Log.error("One of the model values was nil!")
            return .aModelValueWasNil
        }
    
        // TODO: *2* Seems like we could use an encoding here to deal with sql injection issues.
        let (appMetaDataFieldValue, appMetaDataFieldName) = getInsertFieldValueAndName(fieldValue: upload.appMetaData, fieldName: Upload.appMetaDataKey)

        let (appMetaDataVersionFieldValue, appMetaDataVersionFieldName) = getInsertFieldValueAndName(fieldValue: upload.appMetaDataVersion, fieldName: Upload.appMetaDataVersionKey, fieldIsString:false)
        
        let (fileGroupUUIDFieldValue, fileGroupUUIDFieldName) = getInsertFieldValueAndName(fieldValue: upload.fileGroupUUID, fieldName: Upload.fileGroupUUIDKey)
        
        let (fileSizeFieldValue, fileSizeFieldName) = getInsertFieldValueAndName(fieldValue: upload.fileSizeBytes, fieldName: Upload.fileSizeBytesKey, fieldIsString:false)
 
        let (mimeTypeFieldValue, mimeTypeFieldName) = getInsertFieldValueAndName(fieldValue: upload.mimeType, fieldName: Upload.mimeTypeKey)
        
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
        
        let (fileVersionFieldValue, fileVersionFieldName) = getInsertFieldValueAndName(fieldValue: upload.fileVersion, fieldName: Upload.fileVersionKey, fieldIsString:false)
        
        let query = "INSERT INTO \(tableName) (\(Upload.fileUUIDKey), \(Upload.userIdKey), \(Upload.deviceUUIDKey), \(Upload.stateKey), \(Upload.sharingGroupUUIDKey) \(creationDateFieldName) \(updateDateFieldName) \(fileSizeFieldName) \(mimeTypeFieldName) \(appMetaDataFieldName) \(appMetaDataVersionFieldName) \(fileVersionFieldName) \(fileGroupUUIDFieldName)) VALUES('\(upload.fileUUID!)', \(upload.userId!), '\(upload.deviceUUID!)', '\(upload.state!.rawValue)', '\(upload.sharingGroupUUID!)' \(creationDateFieldValue) \(updateDateFieldValue) \(fileSizeFieldValue) \(mimeTypeFieldValue) \(appMetaDataFieldValue) \(appMetaDataVersionFieldValue) \(fileVersionFieldValue) \(fileGroupUUIDFieldValue));"
        
        if db.connection.query(statement: query) {
            return .success(uploadId: db.connection.lastInsertId())
        }
        else if db.connection.errorCode() == Database.duplicateEntryForKey {
            return .duplicateEntry
        }
        else {
            let error = db.error
            let message = "Could not insert into \(tableName): \(error)"
            Log.error(message)
            return .otherError(message)
        }
    }
    
    // The Upload model *must* have an uploadId
    func update(upload:Upload, fileInFileIndex:Bool=false) -> Bool {
        if upload.uploadId == nil || haveNilField(upload: upload, fileInFileIndex:fileInFileIndex) {
            Log.error("One of the model values was nil!")
            return false
        }
    
        // TODO: *2* Seems like we could use an encoding here to deal with sql injection issues.
        let appMetaDataField = getUpdateFieldSetter(fieldValue: upload.appMetaData, fieldName: Upload.appMetaDataKey)
        
        let fileSizeBytesField = getUpdateFieldSetter(fieldValue: upload.fileSizeBytes, fieldName: Upload.fileSizeBytesKey, fieldIsString: false)
        
        let mimeTypeField = getUpdateFieldSetter(fieldValue: upload.mimeType, fieldName: Upload.mimeTypeKey)
        
        let fileGroupUUIDField = getUpdateFieldSetter(fieldValue: upload.fileGroupUUID, fieldName: Upload.fileGroupUUIDKey)
        
        let query = "UPDATE \(tableName) SET fileUUID='\(upload.fileUUID!)', userId=\(upload.userId!), fileVersion=\(upload.fileVersion!), state='\(upload.state!.rawValue)', deviceUUID='\(upload.deviceUUID!)' \(fileSizeBytesField) \(appMetaDataField) \(mimeTypeField) \(fileGroupUUIDField) WHERE uploadId=\(upload.uploadId!)"
        
        if db.connection.query(statement: query) {
            // "When using UPDATE, MySQL will not update columns where the new value is the same as the old value. This creates the possibility that mysql_affected_rows may not actually equal the number of rows matched, only the number of rows that were literally affected by the query." From: https://dev.mysql.com/doc/apis-php/en/apis-php-function.mysql-affected-rows.html
            if db.connection.numberAffectedRows() <= 1 {
                return true
            }
            else {
                Log.error("Did not have <= 1 row updated: \(db.connection.numberAffectedRows())")
                return false
            }
        }
        else {
            let error = db.error
            Log.error("Could not update \(tableName): \(error)")
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
    case uploads([Upload])
    case error(Swift.Error)
    }
    
    // With nil `andState` parameter value, returns both file uploads and upload deletions.
    func uploadedFiles(forUserId userId: UserId, deviceUUID: String, andState state:UploadState? = nil) -> UploadedFilesResult {
        let selectUploadedFiles = select(forUserId: userId, deviceUUID: deviceUUID, andState: state)

        var result:[Upload] = []
        
        selectUploadedFiles.forEachRow { rowModel in
            let rowModel = rowModel as! Upload
            result.append(rowModel)
        }
        
        if selectUploadedFiles.forEachRowStatus == nil {
            return .uploads(result)
        }
        else {
            return .error(selectUploadedFiles.forEachRowStatus!)
        }
    }
    
    static func uploadsToFileInfo(uploads: [Upload]) -> [FileInfo] {
        var result = [FileInfo]()
        
        for upload in uploads {
            let fileInfo = FileInfo()!
            
            fileInfo.fileUUID = upload.fileUUID
            fileInfo.fileVersion = upload.fileVersion
            fileInfo.deleted = upload.state == .toDeleteFromFileIndex
            fileInfo.fileSizeBytes = upload.fileSizeBytes
            fileInfo.mimeType = upload.mimeType
            fileInfo.creationDate = upload.creationDate
            fileInfo.updateDate = upload.updateDate
            fileInfo.fileGroupUUID = upload.fileGroupUUID
            fileInfo.sharingGroupUUID = upload.sharingGroupUUID
            
            result += [fileInfo]
        }
        
        return result
    }

    static func isValidAppMetaDataUpload(currServerAppMetaDataVersion: AppMetaDataVersionInt?, currServerAppMetaData: String?, optionalUpload appMetaData:AppMetaData?) -> Bool {

        if appMetaData == nil {
            // Doesn't matter what the current app meta data is-- we're not changing it.
            return true
        }
        else {
            return isValidAppMetaDataUpload(currServerAppMetaDataVersion: currServerAppMetaDataVersion, currServerAppMetaData: currServerAppMetaData, upload: appMetaData!)
        }
    }
    
    static func isValidAppMetaDataUpload(currServerAppMetaDataVersion: AppMetaDataVersionInt?, currServerAppMetaData: String?, upload appMetaData:AppMetaData) -> Bool {

        if currServerAppMetaDataVersion == nil {
            // No app meta data yet on server for this file. Need 0 first version.
            return appMetaData.version == 0
        }
        else {
            // Already have app meta data on server-- must have next version.
            return appMetaData.version == currServerAppMetaDataVersion! + 1
        }
    }
}
