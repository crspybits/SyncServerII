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
    // We don't give the deviceUUID when updating the fileIndex for an upload deletion.
    var deviceUUID:String?
    
    static let fileGroupUUIDKey = "fileGroupUUID"
    // Not all files have to be associated with a file group.
    var fileGroupUUID:String?
    
    // Currently allowing files to be in exactly one sharing group.
    static let sharingGroupIdKey = "sharingGroupId"
    var sharingGroupId: SharingGroupId!
    
    static let creationDateKey = "creationDate"
    // We don't give the `creationDate` when updating the fileIndex for versions > 0.
    var creationDate:Date?
    
    static let updateDateKey = "updateDate"
    var updateDate:Date!
    
    // OWNER
    /// The userId of the (effective) owning user of v0 of the file. The userId doesn't change beyond that point-- the v0 owner is always the owner.
    static let userIdKey = "userId"
    var userId: UserId!
    
    static let mimeTypeKey = "mimeType"
    var mimeType: String!
    
    static let appMetaDataKey = "appMetaData"
    var appMetaData: String?
    
    static let appMetaDataVersionKey = "appMetaDataVersion"
    var appMetaDataVersion: AppMetaDataVersionInt?
    
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

            case FileIndex.fileGroupUUIDKey:
                fileGroupUUID = newValue as! String?
                
            case FileIndex.sharingGroupIdKey:
                sharingGroupId = newValue as! SharingGroupId?
                
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
                
            case FileIndex.appMetaDataKey:
                appMetaData = newValue as! String?
                
            case FileIndex.appMetaDataVersionKey:
                appMetaDataVersion = newValue as! AppMetaDataVersionInt?
            
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
        return "fileIndexId: \(fileIndexId); fileUUID: \(fileUUID); deviceUUID: \(deviceUUID ?? ""); creationDate: \(String(describing: creationDate)); updateDate: \(updateDate); userId: \(userId); mimeTypeKey: \(mimeType); appMetaData: \(String(describing: appMetaData)); appMetaDataVersion: \(String(describing: appMetaDataVersion)); deleted: \(deleted); fileVersion: \(fileVersion); fileSizeBytes: \(fileSizeBytes)"
    }
}

class FileIndexRepository : Repository {
    private(set) var db:Database!
    
    init(_ db:Database) {
        self.db = db
    }
    
    var tableName:String {
        return FileIndexRepository.tableName
    }
    
    static var tableName:String {
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
            
            // identifies a group of files (assigned by app)
            "fileGroupUUID VARCHAR(\(Database.uuidLength)), " +
            
            "sharingGroupId BIGINT NOT NULL, " +

            // Not saying "NOT NULL" here only because in the first deployed version of the database, I didn't have these dates.
            "creationDate DATETIME," +
            "updateDate DATETIME," +

            // MIME type of the file
            "mimeType VARCHAR(\(Database.maxMimeTypeLength)) NOT NULL, " +

            // App-specific meta data
            "appMetaData TEXT, " +

            // true if file has been deleted, false if not.
            "deleted BOOL NOT NULL, " +
            
            "fileVersion INT NOT NULL, " +
            
            // Making this optional because appMetaData is optional. If there is app meta data, this must not be null.
            "appMetaDataVersion INT, " +

            "fileSizeBytes BIGINT NOT NULL, " +

            "FOREIGN KEY (sharingGroupId) REFERENCES \(SharingGroupRepository.tableName)(\(SharingGroup.sharingGroupIdKey)), " +

            "UNIQUE (fileUUID, sharingGroupId), " +
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
            
            // 2/25/18; Evolution 2: Remove the cloudFolderName column
            let cloudFolderNameKey = "cloudFolderName"
            if db.columnExists(cloudFolderNameKey, in: tableName) == true {
                if !db.removeColumn(cloudFolderNameKey, from: tableName) {
                    return .failure(.columnRemoval)
                }
            }
            
            // 3/23/18; Evolution 3: Add the appMetaDataVersion column.
            if db.columnExists(FileIndex.appMetaDataVersionKey, in: tableName) == false {
                if !db.addColumn("\(FileIndex.appMetaDataVersionKey) INT", to: tableName) {
                    return .failure(.columnCreation)
                }
            }
            
            // 4/19/18; Evolution 4: Add in fileGroupUUID
            if db.columnExists(FileIndex.fileGroupUUIDKey, in: tableName) == false {
                if !db.addColumn("\(FileIndex.fileGroupUUIDKey) VARCHAR(\(Database.uuidLength))", to: tableName) {
                    return .failure(.columnCreation)
                }
            }
            
        default:
            break
        }
        
        return result
    }
    
    private func haveNilFieldForAdd(fileIndex:FileIndex) -> Bool {
        return fileIndex.fileUUID == nil || fileIndex.userId == nil || fileIndex.mimeType == nil || fileIndex.deviceUUID == nil || fileIndex.deleted == nil || fileIndex.fileVersion == nil || fileIndex.fileSizeBytes == nil || fileIndex.creationDate == nil || fileIndex.updateDate == nil
    }
    
    // uploadId in the model is ignored and the automatically generated uploadId is returned if the add is successful.
    func add(fileIndex:FileIndex) -> Int64? {
        if haveNilFieldForAdd(fileIndex: fileIndex) {
            Log.error("One of the model values was nil: \(fileIndex)")
            return nil
        }
        
        let deletedValue = fileIndex.deleted == true ? 1 : 0
        
        let creationDateValue = DateExtras.date(fileIndex.creationDate!, toFormat: .DATETIME)
        let updateDateValue = DateExtras.date(fileIndex.updateDate, toFormat: .DATETIME)
        
        // TODO: *2* Seems like we could use an encoding here to deal with sql injection issues.
        let (appMetaDataFieldValue, appMetaDataFieldName) = getInsertFieldValueAndName(fieldValue: fileIndex.appMetaData, fieldName: Upload.appMetaDataKey)

        let (appMetaDataVersionFieldValue, appMetaDataVersionFieldName) = getInsertFieldValueAndName(fieldValue: fileIndex.appMetaDataVersion, fieldName: Upload.appMetaDataVersionKey, fieldIsString:false)
        
        let (fileGroupUUIDFieldValue, fileGroupUUIDFieldName) = getInsertFieldValueAndName(fieldValue: fileIndex.fileGroupUUID, fieldName: FileIndex.fileGroupUUIDKey)
        
        let query = "INSERT INTO \(tableName) (\(FileIndex.fileUUIDKey), \(FileIndex.userIdKey), \(FileIndex.deviceUUIDKey), \(FileIndex.creationDateKey), \(FileIndex.updateDateKey), \(FileIndex.mimeTypeKey), \(FileIndex.deletedKey), \(FileIndex.fileVersionKey), \(FileIndex.fileSizeBytesKey) \(appMetaDataFieldName) \(appMetaDataVersionFieldName) \(fileGroupUUIDFieldName) ) VALUES('\(fileIndex.fileUUID!)', \(fileIndex.userId!), '\(fileIndex.deviceUUID!)', '\(creationDateValue)', '\(updateDateValue)', '\(fileIndex.mimeType!)', \(deletedValue), \(fileIndex.fileVersion!), \(fileIndex.fileSizeBytes!) \(appMetaDataFieldValue) \(appMetaDataVersionFieldValue) \(fileGroupUUIDFieldValue) );"
        
        if db.connection.query(statement: query) {
            return db.connection.lastInsertId()
        }
        else {
            let error = db.error
            Log.error("Could not insert row into \(tableName): \(error)")
            return nil
        }
    }
    
    private func haveNilFieldForUpdate(fileIndex:FileIndex, updateType: UpdateType) -> Bool {
        // OWNER
        // Allowing a nil userId for update because the v0 owner of a file is always the owner of the file. i.e., for v1, v2 etc. of a file, we don't update the userId.
        let result = fileIndex.fileUUID == nil || fileIndex.deleted == nil
        
        switch updateType {
        case .uploadDeletion:
            return result || fileIndex.fileVersion == nil
            
        case .uploadAppMetaData:
            return result
            
        case .uploadFile:
            return result || fileIndex.fileVersion == nil || fileIndex.deviceUUID == nil
        }
    }
    
    enum UpdateType {
        case uploadFile
        case uploadDeletion
        case uploadAppMetaData
    }
    
    // The FileIndex model *must* have a fileIndexId
    // OWNER: userId is ignored in the fileIndex-- the v0 owner is the permanent owner.
    func update(fileIndex:FileIndex, updateType: UpdateType = .uploadFile) -> Bool {
        if fileIndex.fileIndexId == nil ||
            haveNilFieldForUpdate(fileIndex: fileIndex, updateType:updateType) {
            Log.error("One of the model values was nil: \(fileIndex)")
            return false
        }
        
        // TODO: *2* Seems like we could use an encoding here to deal with sql injection issues.
        let appMetaDataField = getUpdateFieldSetter(fieldValue: fileIndex.appMetaData, fieldName: FileIndex.appMetaDataKey)

        let appMetaDataVersionField = getUpdateFieldSetter(fieldValue: fileIndex.appMetaDataVersion, fieldName: FileIndex.appMetaDataVersionKey, fieldIsString: false)
        
        let fileSizeBytesField = getUpdateFieldSetter(fieldValue: fileIndex.fileSizeBytes, fieldName: FileIndex.fileSizeBytesKey, fieldIsString: false)
        
        let mimeTypeField = getUpdateFieldSetter(fieldValue: fileIndex.mimeType, fieldName: FileIndex.mimeTypeKey)

        let deviceUUIDField = getUpdateFieldSetter(fieldValue: fileIndex.deviceUUID, fieldName: FileIndex.deviceUUIDKey)
        
        let fileVersionField = getUpdateFieldSetter(fieldValue: fileIndex.fileVersion, fieldName: FileIndex.fileVersionKey, fieldIsString: false)
        
        let fileGroupUUIDField = getUpdateFieldSetter(fieldValue: fileIndex.fileGroupUUID, fieldName: FileIndex.fileGroupUUIDKey)
        
        var updateDateValue:String?
        if fileIndex.updateDate != nil {
            updateDateValue = DateExtras.date(fileIndex.updateDate, toFormat: .DATETIME)
        }
        let updateDateField = getUpdateFieldSetter(fieldValue: updateDateValue, fieldName: FileIndex.updateDateKey)
        
        let deletedValue = fileIndex.deleted == true ? 1 : 0

        let query = "UPDATE \(tableName) SET \(FileIndex.fileUUIDKey)='\(fileIndex.fileUUID!)', \(FileIndex.deletedKey)=\(deletedValue) \(appMetaDataField) \(fileSizeBytesField) \(mimeTypeField) \(deviceUUIDField) \(updateDateField) \(appMetaDataVersionField) \(fileVersionField) \(fileGroupUUIDField) WHERE \(FileIndex.fileIndexIdKey)=\(fileIndex.fileIndexId!)"
        
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
        case primaryKeys(sharingGroupId: SharingGroupId, fileUUID:String)
        
        var description : String {
            switch self {
            case .fileIndexId(let fileIndexId):
                return "fileIndexId(\(fileIndexId))"
            case .userId(let userId):
                return "userId(\(userId))"
            case .primaryKeys(let sharingGroupId, let fileUUID):
                return "sharingGroupId(\(sharingGroupId)); fileUUID(\(fileUUID))"
            }
        }
    }
    
    func lookupConstraint(key:LookupKey) -> String {
        switch key {
        case .fileIndexId(let fileIndexId):
            return "fileIndexId = \(fileIndexId)"
        case .userId(let userId):
            return "userId = \(userId)"
        case .primaryKeys(let sharingGroupId, let fileUUID):
            return "sharingGroupId = \(sharingGroupId) and fileUUID = '\(fileUUID)'"
        }
    }
    
    /* For each entry in Upload for the userId/deviceUUID that is in the uploaded state, we need to do the following:
    
        1) If there is no file in the FileIndex for the userId/fileUUID, then a new entry needs to be inserted into the FileIndex. This should be version 0 of the file. The deviceUUID is taken from the device uploading the file.
        2) If there is already a file in the FileIndex for the userId/fileUUID, then the version number we have in Uploads should be the version number in the FileIndex + 1 (if not, it is an error). Update the FileIndex with the new info from Upload, if no error. More specifically, the deviceUUID of the uploading device will replace that currently in the FileIndex-- because the new file in cloud storage is named:
                <fileUUID>.<Uploading-deviceUUID>.<fileVersion>
            where <fileVersion> is the new file version, and
                <Uploading-deviceUUID> is the device UUID of the uploading device.
    */
    // Returns nil on failure, and on success returns the number of uploads transferred.
    func transferUploads(uploadUserId: UserId, owningUserId: UserId, uploadingDeviceUUID:String, uploadRepo:UploadRepository) -> Int32? {
        
        var error = false
        var numberTransferred:Int32 = 0
        
        let uploadSelect = uploadRepo.select(forUserId: uploadUserId, deviceUUID: uploadingDeviceUUID)
        uploadSelect.forEachRow { rowModel in
            if error {
                return
            }
            
            let upload = rowModel as! Upload
            
            // This will a) mark the FileIndex entry as deleted for toDeleteFromFileIndex, and b) mark it as not deleted for *both* uploadingUndelete and uploading files. So, effectively, it does part of our upload undelete for us.
            let uploadDeletion = upload.state == .toDeleteFromFileIndex

            let fileIndex = FileIndex()
            fileIndex.fileSizeBytes = upload.fileSizeBytes
            fileIndex.deleted = uploadDeletion
            fileIndex.fileUUID = upload.fileUUID
            
            // If this an uploadDeletion or updating app meta data, it seems inappropriate to update the deviceUUID in the file index-- all we're doing is marking it as deleted.
            if !uploadDeletion && upload.state != .uploadingAppMetaData {
                fileIndex.deviceUUID = uploadingDeviceUUID
            }
            
            fileIndex.mimeType = upload.mimeType
            fileIndex.appMetaData = upload.appMetaData
            fileIndex.appMetaDataVersion = upload.appMetaDataVersion
            fileIndex.fileGroupUUID = upload.fileGroupUUID
            
            if let uploadFileVersion = upload.fileVersion {
                fileIndex.fileVersion = uploadFileVersion

                if uploadFileVersion == 0 {
                    fileIndex.creationDate = upload.creationDate
                    
                    // OWNER
                    // version 0 of a file establishes the owning user. The owning user doesn't change if new versions are uploaded.
                    fileIndex.userId = owningUserId
                    
                    // Similarly, the sharing group id doesn't change over time.
                    fileIndex.sharingGroupId = upload.sharingGroupId
                }
                
                fileIndex.updateDate = upload.updateDate
            }
            else if upload.state != .uploadingAppMetaData {
                Log.error("No file version, and not uploading app meta data.")
                error = true
                return
            }
            
            let key = LookupKey.primaryKeys(sharingGroupId: upload.sharingGroupId, fileUUID: upload.fileUUID)
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
                else if upload.state != .uploadingAppMetaData {
                    guard upload.fileVersion == (existingFileIndex.fileVersion + 1) else {
                        Log.error("Did not have next version of file!")
                        error = true
                        return
                    }
                }

                fileIndex.fileIndexId = existingFileIndex.fileIndexId
                
                var updateType:UpdateType = .uploadFile
                if uploadDeletion {
                    updateType = .uploadDeletion
                }
                else if upload.state == .uploadingAppMetaData {
                    updateType = .uploadAppMetaData
                }
                
                guard self.update(fileIndex: fileIndex, updateType: updateType) else {
                    Log.error("Could not update FileIndex!")
                    error = true
                    return
                }
                
            case .noObjectFound:
                if upload.state == .uploadingAppMetaData {
                    Log.error("Attempting to upload app meta data for a file not present in the file index: \(key)!")
                    error = true
                    return
                }
                else if uploadDeletion {
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
     
    func fileIndex(forSharingGroupId sharingGroupId: SharingGroupId) -> FileIndexResult {
        let query = "select * from \(tableName) where sharingGroupId = \(sharingGroupId)"
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
            fileInfo.fileVersion = rowModel.fileVersion
            fileInfo.deleted = rowModel.deleted
            fileInfo.fileSizeBytes = rowModel.fileSizeBytes
            fileInfo.mimeType = rowModel.mimeType
            fileInfo.creationDate = rowModel.creationDate
            fileInfo.updateDate = rowModel.updateDate
            fileInfo.appMetaDataVersion = rowModel.appMetaDataVersion
            fileInfo.fileGroupUUID = rowModel.fileGroupUUID
            fileInfo.owningUserId = rowModel.userId
            fileInfo.sharingGroupId = rowModel.sharingGroupId
            
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
