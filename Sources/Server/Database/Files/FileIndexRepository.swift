//
//  FileIndexRepository.swift
//  Server
//
//  Created by Christopher Prince on 1/21/17.
//
//

// Meta data for files currently in cloud storage.

import Foundation
import LoggerAPI
import SyncServerShared

typealias FileIndexId = Int64

class FileIndex : NSObject, Model, Filenaming {
    static let fileIndexIdKey = "fileIndexId"
    var fileIndexId: FileIndexId!
    
    static let fileUUIDKey = "fileUUID"
    var fileUUID: String!
    
    static let deviceUUIDKey = "deviceUUID"
    var deviceUUID:String!
    
    static let creationDateKey = "creationDate"
    var creationDate:Date!
    
    // Mostly for future use since we're not yet allowing multiple file versions.
    static let updateDateKey = "updateDate"
    var updateDate:Date!
    
    // The userId of the owning user.
    static let userIdKey = "userId"
    var userId: UserId!
    
    static let mimeTypeKey = "mimeType"
    var mimeType: String!
    
    static let cloudFolderNameKey = "cloudFolderName"
    var cloudFolderName: String!
    
    static let appMetaDataKey = "appMetaData"
    var appMetaData: String?
    
    static let deletedKey = "deleted"
    var deleted:Bool!
    
    static let fileVersionKey = "fileVersion"
    var fileVersion: FileVersionInt!
    
    static let fileSizeBytesKey = "fileSizeBytes"
    var fileSizeBytes: Int64!
    
    subscript(key:String) -> Any? {
        set {
            switch key {
            case FileIndex.fileIndexIdKey:
                fileIndexId = newValue as! FileIndexId?

            case FileIndex.fileUUIDKey:
                fileUUID = newValue as! String?
                
            case FileIndex.deviceUUIDKey:
                deviceUUID = newValue as! String?
                
            case FileIndex.creationDateKey:
                creationDate = newValue as! Date?

            case FileIndex.updateDateKey:
                updateDate = newValue as! Date?
                
            case FileIndex.userIdKey:
                userId = newValue as! UserId?
                
            case FileIndex.mimeTypeKey:
                mimeType = newValue as! String?
                
            case FileIndex.cloudFolderNameKey:
                cloudFolderName = newValue as! String?
                
            case FileIndex.appMetaDataKey:
                appMetaData = newValue as! String?
            
            case FileIndex.deletedKey:
                deleted = newValue as! Bool?
                
            case FileIndex.fileVersionKey:
                fileVersion = newValue as! FileVersionInt?
                
            case FileIndex.fileSizeBytesKey:
                fileSizeBytes = newValue as! Int64?
                
            default:
                assert(false)
            }
        }
        
        get {
            return getValue(forKey: key)
        }
    }
    
    override init() {
        super.init()
    }
    
    func typeConvertersToModel(propertyName:String) -> ((_ propertyValue:Any) -> Any?)? {
        switch propertyName {
            case FileIndex.deletedKey:
                return {(x:Any) -> Any? in
                    return (x as! Int8) == 1
                }
            
            case FileIndex.creationDateKey:
                return {(x:Any) -> Any? in
                    return DateExtras.date(x as! String, fromFormat: .DATETIME)
                }

            case FileIndex.updateDateKey:
                return {(x:Any) -> Any? in
                    return DateExtras.date(x as! String, fromFormat: .DATETIME)
                }
            
            default:
                return nil
        }
    }
    
    override var description : String {
        return "fileIndexId: \(fileIndexId); fileUUID: \(fileUUID); deviceUUID: \(deviceUUID); creationDate: \(creationDate); updateDate: \(updateDate); userId: \(userId); mimeTypeKey: \(mimeType); appMetaData: \(String(describing: appMetaData)); deleted: \(deleted); fileVersion: \(fileVersion); fileSizeBytes: \(fileSizeBytes); cloudFolderName: \(cloudFolderName)"
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
    
    func upcreate() -> Database.TableUpcreateResult {
        let createColumns =
            "(fileIndexId BIGINT NOT NULL AUTO_INCREMENT, " +
                        
            // permanent reference to file (assigned by app)
            "fileUUID VARCHAR(\(Database.uuidLength)) NOT NULL, " +
        
            // reference into User table
            // TODO: *2* Make this a foreign reference.
            "userId BIGINT NOT NULL, " +
            
            // identifies a specific mobile device (assigned by app)
            // This plays a different role than it did in the Upload table. Here, it forms part of the filename in cloud storage, and thus must be retained. We will ignore this field otherwise, i.e., we will not have two entries in this table for the same userId, fileUUID pair.
            "deviceUUID VARCHAR(\(Database.uuidLength)) NOT NULL, " +
            
            // Not saying "NOT NULL" here only because in the first deployed version of the database, I didn't have these dates.
            "creationDate DATETIME," +
            "updateDate DATETIME," +

            // MIME type of the file
            "mimeType VARCHAR(\(Database.maxMimeTypeLength)) NOT NULL, " +

            "cloudFolderName VARCHAR(\(Database.maxCloudFolderNameLength)) NOT NULL, " +

            // App-specific meta data
            "appMetaData TEXT, " +

            // true if file has been deleted, false if not.
            "deleted BOOL NOT NULL, " +
            
            "fileVersion INT NOT NULL, " +

            "fileSizeBytes BIGINT NOT NULL, " +

            "UNIQUE (fileUUID, userId), " +
            "UNIQUE (fileIndexId))"
        
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
    
    private func columnNames(appMetaDataFieldName:String = "appMetaData,") -> String {
        return "fileUUID, userId, deviceUUID, creationDate, updateDate, mimeType, \(appMetaDataFieldName) deleted, fileVersion, fileSizeBytes, cloudFolderName"
    }
    
    private func haveNilFieldForAdd(fileIndex:FileIndex) -> Bool {
        return fileIndex.fileUUID == nil || fileIndex.userId == nil || fileIndex.mimeType == nil || fileIndex.deviceUUID == nil || fileIndex.deleted == nil || fileIndex.fileVersion == nil || fileIndex.fileSizeBytes == nil || fileIndex.cloudFolderName == nil || fileIndex.creationDate == nil || fileIndex.updateDate == nil
    }
    
    // uploadId in the model is ignored and the automatically generated uploadId is returned if the add is successful.
    func add(fileIndex:FileIndex) -> Int64? {
        if haveNilFieldForAdd(fileIndex: fileIndex) {
            Log.error("One of the model values was nil: \(fileIndex)")
            return nil
        }
    
        var appMetaDataFieldValue = ""
        var columns = columnNames(appMetaDataFieldName: "")
        
        if fileIndex.appMetaData != nil {
            // TODO: *2* Seems like we could use an encoding here to deal with sql injection issues.
            appMetaDataFieldValue = ", '\(fileIndex.appMetaData!)'"
            
            columns = columnNames()
        }
        
        let deletedValue = fileIndex.deleted == true ? 1 : 0
        
        let creationDateValue = DateExtras.date(fileIndex.creationDate, toFormat: .DATETIME)
        let updateDateValue = DateExtras.date(fileIndex.updateDate, toFormat: .DATETIME)

        let query = "INSERT INTO \(tableName) (\(columns)) VALUES('\(fileIndex.fileUUID!)', \(fileIndex.userId!), '\(fileIndex.deviceUUID!)', '\(creationDateValue)', '\(updateDateValue)', '\(fileIndex.mimeType!)' \(appMetaDataFieldValue), \(deletedValue), \(fileIndex.fileVersion!), \(fileIndex.fileSizeBytes!), '\(fileIndex.cloudFolderName!)');"
        
        if db.connection.query(statement: query) {
            return db.connection.lastInsertId()
        }
        else {
            let error = db.error
            Log.error("Could not insert row into \(tableName): \(error)")
            return nil
        }
    }
    
    private func haveNilFieldForUpdate(fileIndex:FileIndex) -> Bool {
        return fileIndex.fileUUID == nil || fileIndex.userId == nil || fileIndex.deviceUUID == nil || fileIndex.deleted == nil || fileIndex.fileVersion == nil
    }
    
    // The FileIndex model *must* have a fileIndexId
    func update(fileIndex:FileIndex) -> Bool {
        if fileIndex.fileIndexId == nil ||
            haveNilFieldForUpdate(fileIndex: fileIndex) {
            Log.error("One of the model values was nil: \(fileIndex)")
            return false
        }
        
        // TODO: *2* Seems like we could use an encoding here to deal with sql injection issues.
        let appMetaDataField = getUpdateFieldSetter(fieldValue: fileIndex.appMetaData, fieldName: "appMetaData")

        let fileSizeBytesField = getUpdateFieldSetter(fieldValue: fileIndex.fileSizeBytes, fieldName: "fileSizeBytes", fieldIsString: false)
        
        let mimeTypeField = getUpdateFieldSetter(fieldValue: fileIndex.mimeType, fieldName: "mimeType")
        
        let cloudFolderNameField = getUpdateFieldSetter(fieldValue: fileIndex.cloudFolderName, fieldName: "cloudFolderName")
        
        let deletedValue = fileIndex.deleted == true ? 1 : 0

        let query = "UPDATE \(tableName) SET fileUUID='\(fileIndex.fileUUID!)', userId=\(fileIndex.userId!), deviceUUID='\(fileIndex.deviceUUID!)', deleted=\(deletedValue), fileVersion=\(fileIndex.fileVersion!) \(appMetaDataField) \(fileSizeBytesField) \(mimeTypeField) \(cloudFolderNameField) WHERE fileIndexId=\(fileIndex.fileIndexId!)"
        
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
            return "fileIndexId = \(fileIndexId)"
        case .userId(let userId):
            return "userId = \(userId)"
        case .primaryKeys(let userId, let fileUUID):
            return "userId = \(userId) and fileUUID = '\(fileUUID)'"
        }
    }
    
    /* For each entry in Upload for the userId/deviceUUID that is in the uploaded state, we need to do the following:
    
        1) If there is no file in the FileIndex for the userId/fileUUID, then a new entry needs to be inserted into the FileIndex. This should be version 0 of the file.
        2) If there is already a file in the FileIndex for the userId/deviceUUID, then the version number we have in Uploads should be the version number in the FileIndex + 1 (if not, it is an error). Update the FileIndex with the new info from Upload, if no error.
    */
    // Returns nil on failure, and on success returns the number of uploads transferred.
    func transferUploads(uploadUserId: UserId, owningUserId: UserId, deviceUUID:String, uploadRepo:UploadRepository) -> Int32? {
        
        var error = false
        var numberTransferred:Int32 = 0
        
        let uploadSelect = uploadRepo.select(forUserId: uploadUserId, deviceUUID: deviceUUID)
        uploadSelect.forEachRow { rowModel in
            if error {
                return
            }
            
            let upload = rowModel as! Upload
            
            let uploadDeletion = upload.state == .toDeleteFromFileIndex

            let fileIndex = FileIndex()
            fileIndex.fileSizeBytes = upload.fileSizeBytes
            fileIndex.deleted = uploadDeletion
            fileIndex.fileUUID = upload.fileUUID
            fileIndex.deviceUUID = deviceUUID
            fileIndex.fileVersion = upload.fileVersion
            fileIndex.mimeType = upload.mimeType
            fileIndex.userId = owningUserId
            fileIndex.appMetaData = upload.appMetaData
            fileIndex.cloudFolderName = upload.cloudFolderName
            fileIndex.creationDate = upload.creationDate
            fileIndex.updateDate = upload.updateDate
            
            let key = LookupKey.primaryKeys(userId: "\(owningUserId)", fileUUID: upload.fileUUID)
            let result = self.lookup(key: key, modelInit: FileIndex.init)
            
            switch result {
            case .error(_):
                error = true
                return
                
            case .found(let object):
                let existingFileIndex = object as! FileIndex

                if uploadDeletion {
                    guard upload.fileVersion == existingFileIndex.fileVersion else {
                        Log.error("Did not specify current version of file in upload deletion!")
                        error = true
                        return
                    }
                }
                else {
                    guard upload.fileVersion == existingFileIndex.fileVersion + FileVersionInt(1) else {
                        Log.error("Did not have next version of file!")
                        error = true
                        return
                    }
                }
                
                // The file we are deleting is named in cloud storage by the fileUUID, deviceUUID *currently in the file index*, and the version. So we have to keep the existing deviceUUID.
                fileIndex.deviceUUID = existingFileIndex.deviceUUID
                
                fileIndex.fileIndexId = existingFileIndex.fileIndexId
                
                guard self.update(fileIndex: fileIndex) else {
                    Log.error("Could not update FileIndex!")
                    error = true
                    return
                }
                
            case .noObjectFound:
                if uploadDeletion {
                    Log.error("Attempting to delete a file not present in the file index: \(key)!")
                    error = true
                    return
                }
                else {
                    guard upload.fileVersion == 0 else {
                        Log.error("Did not have version 0 of file!")
                        error = true
                        return
                    }
                    
                    let fileIndexId = self.add(fileIndex: fileIndex)
                    if fileIndexId == nil {
                        Log.error("Could not add new FileIndex!")
                        error = true
                        return
                    }
                }
            }
            
            numberTransferred += 1
        }
        
        if error {
            return nil
        }
        
        if uploadSelect.forEachRowStatus == nil {
            return numberTransferred
        }
        else {
            return nil
        }
    }
    
    enum FileIndexResult {
    case fileIndex([FileInfo])
    case error(String)
    }
     
    func fileIndex(forUserId userId: UserId) -> FileIndexResult {
        let query = "select * from \(tableName) where userId = \(userId)"
        return fileIndex(forSelectQuery: query)
    }
    
    private func fileIndex(forSelectQuery selectQuery: String) -> FileIndexResult {
        let select = Select(db:db, query: selectQuery, modelInit: FileIndex.init, ignoreErrors:false)
        
        var result:[FileInfo] = []
        
        select.forEachRow { rowModel in
            let rowModel = rowModel as! FileIndex

            let fileInfo = FileInfo()!
            fileInfo.fileUUID = rowModel.fileUUID
            fileInfo.deviceUUID = rowModel.deviceUUID
            fileInfo.appMetaData = rowModel.appMetaData
            fileInfo.fileVersion = rowModel.fileVersion
            fileInfo.deleted = rowModel.deleted
            fileInfo.fileSizeBytes = rowModel.fileSizeBytes
            fileInfo.mimeType = rowModel.mimeType
            fileInfo.cloudFolderName = rowModel.cloudFolderName
            fileInfo.creationDate = rowModel.creationDate
            fileInfo.updateDate = rowModel.updateDate
            
            result.append(fileInfo)
        }
        
        if select.forEachRowStatus == nil {
            return .fileIndex(result)
        }
        else {
            return .error("\(select.forEachRowStatus!)")
        }
    }
    
    func fileIndex(forKeys keys: [LookupKey]) -> FileIndexResult {
        if keys.count == 0 {
            return .error("Can't give 0 keys!")
        }
        
        var query = "select * from \(tableName) where "
        var numberValues = 0
        for key in keys {
            if numberValues > 0 {
                query += " or "
            }
            
            query += " (\(lookupConstraint(key: key))) "
            
            numberValues += 1
        }
        
        return fileIndex(forSelectQuery: query)
    }
}
