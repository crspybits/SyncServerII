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
import ServerShared
import ChangeResolvers
import ServerAccount

typealias FileIndexId = Int64

class FileIndex : NSObject, Model {
    
    static let fileIndexIdKey = "fileIndexId"
    var fileIndexId: FileIndexId!
    
    static let fileUUIDKey = "fileUUID"
    var fileUUID: String!
    
    static let deviceUUIDKey = "deviceUUID"
    var deviceUUID:String!
    
    static let fileGroupUUIDKey = "fileGroupUUID"
    // Not all files have to be associated with a file group.
    var fileGroupUUID:String?

    static let objectTypeKey = "objectType"
    // Not all files have to be associated with a file group, and thus not all files have a objectType.
    var objectType:String?
    
    // Currently allowing files to be in exactly one sharing group.
    static let sharingGroupUUIDKey = "sharingGroupUUID"
    var sharingGroupUUID: String!
    
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
    
    // Nil only if files are static and changes cannot be applied.
    static let changeResolverNameKey = "changeResolverName"
    var changeResolverName: String?
    
    static let appMetaDataKey = "appMetaData"
    var appMetaData: String?
    
    // When "deleted" files are not fully removed from the system. They are removed from cloud storage, but just marked as deleted in the FileIndex. This effectively also marks the containing file group as deleted.
    static let deletedKey = "deleted"
    var deleted:Bool!
    
    static let fileVersionKey = "fileVersion"
    var fileVersion: FileVersionInt!
    
    static let lastUploadedCheckSumKey = "lastUploadedCheckSum"
    var lastUploadedCheckSum: String?

    static let fileLabelKey = "fileLabel"
    var fileLabel: String?
    
    // For queries; not in this table.
    static let accountTypeKey = "accountType"
    var accountType: String!
    
    subscript(key:String) -> Any? {
        set {
            switch key {
            case FileIndex.fileIndexIdKey:
                fileIndexId = newValue as! FileIndexId?

            case FileIndex.fileUUIDKey:
                fileUUID = newValue as! String?

            case FileIndex.fileGroupUUIDKey:
                fileGroupUUID = newValue as! String?

            case FileIndex.objectTypeKey:
                objectType = newValue as? String
                
            case FileIndex.sharingGroupUUIDKey:
                sharingGroupUUID = newValue as! String?
                
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
            
            case FileIndex.deletedKey:
                deleted = newValue as! Bool?
                
            case FileIndex.fileVersionKey:
                fileVersion = newValue as! FileVersionInt?
                
            case FileIndex.lastUploadedCheckSumKey:
                lastUploadedCheckSum = newValue as! String?
                
            case FileIndex.changeResolverNameKey:
                changeResolverName = newValue as? String

            case FileIndex.fileLabelKey:
                fileLabel = newValue as? String
                
            case User.accountTypeKey:
                accountType = newValue as! String?
                
            default:
                Log.debug("key: \(key)")
                assert(false)
            }
        }
        
        get {
            return getValue(forKey: key)
        }
    }
    
    required override init() {
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
        return "fileIndexId: \(String(describing: fileIndexId)); fileUUID: \(String(describing: fileUUID)); deviceUUID: \(deviceUUID ?? ""); creationDate: \(String(describing: creationDate)); updateDate: \(String(describing: updateDate)); userId: \(String(describing: userId)); mimeTypeKey: \(String(describing: mimeType)); appMetaData: \(String(describing: appMetaData)); deleted: \(String(describing: deleted)); fileVersion: \(String(describing: fileVersion)); lastUploadedCheckSum: \(String(describing: lastUploadedCheckSum))"
    }
}

extension FileIndex {
    enum Errors: Swift.Error {
        case couldNotGetOwningUserCreds
        case couldNotConvertToCloudStorage
    }
    
    func getCloudStorage(userRepo: UserRepository, services: UploaderServices) throws -> (Account, CloudStorage) {
        guard let owningUserCreds = FileController.getCreds(forUserId: userId, userRepo: userRepo, accountManager: services.accountManager, accountDelegate: nil) else {
            throw Errors.couldNotGetOwningUserCreds
        }
        
        guard let cloudStorage = owningUserCreds.cloudStorage(mock: services.mockStorage) else {
            throw Errors.couldNotConvertToCloudStorage
        }
        
        return (owningUserCreds, cloudStorage)
    }
}

class FileIndexRepository : Repository, RepositoryLookup, ModelIndexId {
    static let indexIdKey = FileIndex.fileIndexIdKey
    
    enum Errors: Swift.Error {
        case couldNotLookupFileUUID
    }

    private(set) var db:Database!
    
    required init(_ db:Database) {
        self.db = db
    }
    
    var tableName:String {
        return FileIndexRepository.tableName
    }
    
    static var tableName:String {
        return "FileIndex"
    }
    
    static let uniqueFileLabelConstraintName = "UniqueFileLabel"
    static let uniqueFileLabelConstraint = "UNIQUE (fileGroupUUID, fileLabel)"
    
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
            
            // Optionally identifies a group of files (assigned by app). If NULL, the file is not in a file group (it's in a group of size 1).
            "fileGroupUUID VARCHAR(\(Database.uuidLength)), " +
            
            // 9/12/20; Not making this NOT NULL to grandfather in earlier versions of Neebla and because not all files have file groups.
            "objectType VARCHAR(\(FileGroup.maxLengthObjectTypeName)), " +
            
            "sharingGroupUUID VARCHAR(\(Database.uuidLength)) NOT NULL, " +

            // Not saying "NOT NULL" here only because in the first deployed version of the database, I didn't have these dates.
            "creationDate DATETIME," +
            "updateDate DATETIME," +

            // MIME type of the file
            "mimeType VARCHAR(\(Database.maxMimeTypeLength)) NOT NULL, " +

            // App-specific meta data
            "appMetaData TEXT, " +

            // 11/3/20; Optional only because files prior to this don't have this field.
            "fileLabel VARCHAR(\(FileLabel.maxLength)), " +
            
            // true if file has been deleted, false if not.
            "deleted BOOL NOT NULL, " +
            
            "fileVersion INT NOT NULL, " +
            
            // Making this optional because appMetaData is optional. If there is app meta data, this must not be null.
            "appMetaDataVersion INT, " +

            // I've left this as NULL-able for now to deal with migration-- systems in production prior to 10/27/18. In general, this should not be null.
            "lastUploadedCheckSum TEXT, " +

            "FOREIGN KEY (sharingGroupUUID) REFERENCES \(SharingGroupRepository.tableName)(\(SharingGroup.sharingGroupUUIDKey)), " +
            
            "changeResolverName VARCHAR(\(ChangeResolverConstants.maxChangeResolverNameLength)), " +

            // Because file label's must be unique within file group's.
            "CONSTRAINT \(Self.uniqueFileLabelConstraintName) \(Self.uniqueFileLabelConstraint), " +
            
            "UNIQUE (fileUUID, sharingGroupUUID), " +
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
            
            // 4/19/18; Evolution 4: Add in fileGroupUUID
            if db.columnExists(FileIndex.fileGroupUUIDKey, in: tableName) == false {
                if !db.addColumn("\(FileIndex.fileGroupUUIDKey) VARCHAR(\(Database.uuidLength))", to: tableName) {
                    return .failure(.columnCreation)
                }
            }
            
            // 7/15/20; Evolution 5
            if db.columnExists(FileIndex.changeResolverNameKey, in: tableName) == false {
                if !db.addColumn("\(FileIndex.changeResolverNameKey) VARCHAR(\(ChangeResolverConstants.maxChangeResolverNameLength))", to: tableName) {
                    return .failure(.columnCreation)
                }
            }

            if db.columnExists(FileIndex.objectTypeKey, in: tableName) == false {
                if !db.addColumn("\(FileIndex.objectTypeKey) VARCHAR(\(FileGroup.maxLengthObjectTypeName))", to: tableName) {
                    return .failure(.columnCreation)
                }
            }

            if db.columnExists(FileIndex.fileLabelKey, in: tableName) == false {
                if !db.addColumn("\(FileIndex.fileLabelKey) VARCHAR(\(FileLabel.maxLength))", to: tableName) {
                    return .failure(.columnCreation)
                }
            }

            if db.namedConstraintExists(Self.uniqueFileLabelConstraintName, in: tableName) == false {
                if !db.createConstraint(constraint:
                    "\(Self.uniqueFileLabelConstraintName) \(Self.uniqueFileLabelConstraint)", tableName: tableName) {
                    return .failure(.constraintCreation)
                }
            }
            
        default:
            break
        }
        
        return result
    }
    
    private func haveNilFieldForAdd(fileIndex:FileIndex) -> Bool {
        return fileIndex.fileUUID == nil || fileIndex.userId == nil || fileIndex.mimeType == nil || fileIndex.deviceUUID == nil || fileIndex.deleted == nil || fileIndex.fileVersion == nil || fileIndex.lastUploadedCheckSum == nil || fileIndex.creationDate == nil || fileIndex.updateDate == nil || fileIndex.fileLabel == nil
    }
    
    enum AddFileIndexResponse: RetryRequest {
        case success(uploadId: Int64)
        case error
        case deadlock
        
        var shouldRetry: Bool {
            if case .deadlock = self {
                return true
            }
            else {
                return false
            }
        }
    }
    
    // uploadId in the model is ignored and the automatically generated uploadId is returned if the add is successful.
    func add(fileIndex:FileIndex) -> AddFileIndexResponse {
        if haveNilFieldForAdd(fileIndex: fileIndex) {
            Log.error("One of the model values was nil: \(fileIndex)")
            return .error
        }
        
        let insert = Database.PreparedStatement(repo: self, type: .insert)

        insert.add(fieldName: FileIndex.fileVersionKey, value: .int32Optional(fileIndex.fileVersion))
        insert.add(fieldName: FileIndex.userIdKey, value: .int64Optional(fileIndex.userId))
        
        insert.add(fieldName: FileIndex.deletedKey, value: .boolOptional(fileIndex.deleted))

        insert.add(fieldName: FileIndex.fileGroupUUIDKey, value: .stringOptional(fileIndex.fileGroupUUID))
        insert.add(fieldName: FileIndex.objectTypeKey, value: .stringOptional(fileIndex.objectType))
        
        insert.add(fieldName: FileIndex.appMetaDataKey, value: .stringOptional(fileIndex.appMetaData))
        insert.add(fieldName: FileIndex.fileUUIDKey, value: .stringOptional(fileIndex.fileUUID))
        insert.add(fieldName: FileIndex.deviceUUIDKey, value: .stringOptional(fileIndex.deviceUUID))
        insert.add(fieldName: FileIndex.mimeTypeKey, value: .stringOptional(fileIndex.mimeType))
        insert.add(fieldName: FileIndex.lastUploadedCheckSumKey, value: .stringOptional(fileIndex.lastUploadedCheckSum))
        insert.add(fieldName: FileIndex.sharingGroupUUIDKey, value: .stringOptional(fileIndex.sharingGroupUUID))
        insert.add(fieldName: FileIndex.changeResolverNameKey, value: .stringOptional(fileIndex.changeResolverName))

        if let creationDate = fileIndex.creationDate {
            let creationDateValue = DateExtras.date(creationDate, toFormat: .DATETIME)
            insert.add(fieldName: FileIndex.creationDateKey, value: .string(creationDateValue))
        }
        
        if let updateDate = fileIndex.updateDate {
            let updateDateValue = DateExtras.date(updateDate, toFormat: .DATETIME)
            insert.add(fieldName: FileIndex.updateDateKey, value: .string(updateDateValue))
        }
        
        insert.add(fieldName: FileIndex.fileLabelKey, value: .stringOptional(fileIndex.fileLabel))
        
        do {
            try insert.run()
            Log.info("Sucessfully created \(tableName) row")
            return .success(uploadId: db.lastInsertId())
        }
        catch (let error) {
            Log.info("Failed inserting \(tableName) row: \(db.errorCode()); \(db.errorMessage())")
            
            if db.errorCode() == Database.deadlockError {
                return .deadlock
            }
            else {
                let message = "Could not insert into \(tableName): \(error)"
                Log.error(message)
                return .error
            }
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
        
        // DEPRECATED
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
        
        let lastUploadedCheckSumField = getUpdateFieldSetter(fieldValue: fileIndex.lastUploadedCheckSum, fieldName: FileIndex.lastUploadedCheckSumKey)
        
        let mimeTypeField = getUpdateFieldSetter(fieldValue: fileIndex.mimeType, fieldName: FileIndex.mimeTypeKey)

        let deviceUUIDField = getUpdateFieldSetter(fieldValue: fileIndex.deviceUUID, fieldName: FileIndex.deviceUUIDKey)
        
        let fileVersionField = getUpdateFieldSetter(fieldValue: fileIndex.fileVersion, fieldName: FileIndex.fileVersionKey, fieldIsString: false)
        
        let fileGroupUUIDField = getUpdateFieldSetter(fieldValue: fileIndex.fileGroupUUID, fieldName: FileIndex.fileGroupUUIDKey)

        let objectTypeField = getUpdateFieldSetter(fieldValue: fileIndex.objectType, fieldName: FileIndex.objectTypeKey)

        var updateDateValue:String?
        if fileIndex.updateDate != nil {
            updateDateValue = DateExtras.date(fileIndex.updateDate, toFormat: .DATETIME)
        }
        let updateDateField = getUpdateFieldSetter(fieldValue: updateDateValue, fieldName: FileIndex.updateDateKey)
        
        let changeResolverNameField = getUpdateFieldSetter(fieldValue: fileIndex.changeResolverName, fieldName: FileIndex.changeResolverNameKey)
        
        let deletedValue = fileIndex.deleted == true ? 1 : 0
        
        let query = "UPDATE \(tableName) SET \(FileIndex.fileUUIDKey)='\(fileIndex.fileUUID!)', \(FileIndex.deletedKey)=\(deletedValue) \(appMetaDataField) \(lastUploadedCheckSumField) \(mimeTypeField) \(deviceUUIDField) \(updateDateField) \(fileVersionField) \(fileGroupUUIDField) \(changeResolverNameField) \(objectTypeField) WHERE \(FileIndex.fileIndexIdKey)=\(fileIndex.fileIndexId!)"
        
        if db.query(statement: query) {
            // "When using UPDATE, MySQL will not update columns where the new value is the same as the old value. This creates the possibility that mysql_affected_rows may not actually equal the number of rows matched, only the number of rows that were literally affected by the query." From: https://dev.mysql.com/doc/apis-php/en/apis-php-function.mysql-affected-rows.html
            if db.numberAffectedRows() <= 1 {
                return true
            }
            else {
                Log.error("Did not have <= 1 row updated: \(db.numberAffectedRows())")
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
        case primaryKeys(sharingGroupUUID: String, fileUUID:String)
        case sharingGroupUUID(sharingGroupUUID: String)
        case userAndSharingGroup(UserId, sharingGroupUUID: String)
        case fileGroupUUIDAndSharingGroup(fileGroupUUID: String, sharingGroupUUID: String)
        case fileGroupUUIDAndFileLabel(fileGroupUUID: String, fileLabel: String)
        
        var description : String {
            switch self {
            case .fileIndexId(let fileIndexId):
                return "fileIndexId(\(fileIndexId))"
            case .userId(let userId):
                return "userId(\(userId))"
            case .primaryKeys(let sharingGroupUUID, let fileUUID):
                return "sharingGroupUUID(\(sharingGroupUUID)); fileUUID(\(fileUUID))"
            case .sharingGroupUUID(let sharingGroupUUID):
                return "sharingGroupUUID(\(sharingGroupUUID)))"
            case .userAndSharingGroup(let userId, let sharingGroupUUID):
                return "userId(\(userId)); sharingGroupUUID(\(sharingGroupUUID)))"
            case .fileGroupUUIDAndSharingGroup(let fileGroupUUID, let sharingGroupUUID):
                return "fileGroupUUID(\(fileGroupUUID); sharingGroupUUID(\(sharingGroupUUID))"
            case .fileGroupUUIDAndFileLabel(fileGroupUUID: let fileGroupUUID, fileLabel: let fileLabel):
                return "fileGroupUUID(\(fileGroupUUID); fileLabel(\(fileLabel))"
            }
        }
    }
    
    func lookupConstraint(key:LookupKey) -> String {
        switch key {
        case .fileIndexId(let fileIndexId):
            return "fileIndexId = \(fileIndexId)"
        case .userId(let userId):
            return "userId = \(userId)"
        case .primaryKeys(let sharingGroupUUID, let fileUUID):
            return "sharingGroupUUID = '\(sharingGroupUUID)' and fileUUID = '\(fileUUID)'"
        case .sharingGroupUUID(let sharingGroupUUID):
            return "sharingGroupUUID = '\(sharingGroupUUID)'"
        case .userAndSharingGroup(let userId, let sharingGroupUUID):
            return "userId = \(userId) AND sharingGroupUUID = '\(sharingGroupUUID)'"
        case .fileGroupUUIDAndSharingGroup(let fileGroupUUID, let sharingGroupUUID):
            return "fileGroupUUID = '\(fileGroupUUID)' AND sharingGroupUUID = '\(sharingGroupUUID)'"
        case .fileGroupUUIDAndFileLabel(let fileGroupUUID, let fileLabel):
            return "fileGroupUUID = '\(fileGroupUUID)' AND fileLabel = '\(fileLabel)'"
        }
    }
    
    /* For each entry in Upload for the userId/deviceUUID that is in the uploaded state, we need to do the following:
    
        1) If there is no file in the FileIndex for the userId/fileUUID, then a new entry needs to be inserted into the FileIndex. This should be version 0 of the file. The deviceUUID is taken from the device uploading the file.
        2) If there is already a file in the FileIndex for the userId/fileUUID, then the version number we have in Uploads should be the version number in the FileIndex + 1 (if not, it is an error). Update the FileIndex with the new info from Upload, if no error. More specifically, the deviceUUID of the uploading device will replace that currently in the FileIndex-- because the new file in cloud storage is named:
                <fileUUID>.<Uploading-deviceUUID>.<fileVersion>
            where <fileVersion> is the new file version, and
                <Uploading-deviceUUID> is the device UUID of the uploading device.
    */

    enum TransferUploadsResult {
        case success(numberUploadsTransferred: Int32)
        case failure(RequestHandler.FailureResult?)
    }
    
    enum EffectiveOwningUser {
        case success(UserId)
        case failure(RequestHandler.FailureResult)
    }
         
    func transferUploads(uploadUserId: UserId,
        owningUserId: @escaping ()->(EffectiveOwningUser), sharingGroupUUID: String, uploadingDeviceUUID:String, uploadRepo:UploadRepository) -> TransferUploadsResult {
        
        var error = false
        var failureResult:RequestHandler.FailureResult?
        var numberTransferred:Int32 = 0
        
        // [1] Fetch the uploaded files for the user, device, and sharing group.
        guard let uploadSelect = uploadRepo.select(forUserId: uploadUserId, sharingGroupUUID: sharingGroupUUID, deviceUUID: uploadingDeviceUUID) else {
            return .failure(nil)
        }
        
        uploadSelect.forEachRow { [weak self] rowModel in
            guard let self = self else {
                error = true
                return
            }
            
            if error {
                return
            }
            
            let upload = rowModel as! Upload
            
            // This will a) mark the FileIndex entry as deleted for toDeleteFromFileIndex, and b) mark it as not deleted for *both* uploadingUndelete and uploading files. So, effectively, it does part of our upload undelete for us.
            let uploadDeletion = upload.state == .deleteSingleFile

            let fileIndex = FileIndex()
            fileIndex.lastUploadedCheckSum = upload.lastUploadedCheckSum
            fileIndex.deleted = uploadDeletion
            fileIndex.fileUUID = upload.fileUUID
            
            // If this an uploadDeletion, it seems inappropriate to update the deviceUUID in the file index-- all we're doing is marking it as deleted.
            if !uploadDeletion {
                // Using `uploadingDeviceUUID` here, but equivalently use upload.deviceUUID-- they are the same. See [1] above.
                assert(uploadingDeviceUUID == upload.deviceUUID)
                fileIndex.deviceUUID = uploadingDeviceUUID
            }
            
            fileIndex.mimeType = upload.mimeType
            fileIndex.appMetaData = upload.appMetaData
            fileIndex.fileGroupUUID = upload.fileGroupUUID
            fileIndex.objectType = upload.objectType

            if upload.state == .v0UploadCompleteFile {
                fileIndex.fileVersion = 0
                fileIndex.creationDate = upload.creationDate
                fileIndex.changeResolverName = upload.changeResolverName
                
                // OWNER
                // version 0 of a file establishes the owning user. The owning user doesn't change if new versions are uploaded.
                switch owningUserId() {
                case .success(let userId):
                    fileIndex.userId = userId
                case .failure(let failure):
                    failureResult = failure
                    error = true
                    return
                }

                // Similarly, the sharing group id and fileLabel do not change over time.
                fileIndex.sharingGroupUUID = upload.sharingGroupUUID
                fileIndex.fileLabel = upload.fileLabel
            }
            else if upload.state == .vNUploadFileChange {
                guard let fileVersion = upload.fileVersion else {
                    Log.error("No file version, and vNUploadFileChange")
                    error = true
                    return
                }
                
                fileIndex.fileVersion = fileVersion
            }
            else {
                Log.error("No file version.")
                error = true
                return
            }
            
            fileIndex.updateDate = upload.updateDate
            
            let key = LookupKey.primaryKeys(sharingGroupUUID: upload.sharingGroupUUID, fileUUID: upload.fileUUID)
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
                
                guard self.update(fileIndex: fileIndex, updateType: updateType) else {
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
                    guard upload.state == .v0UploadCompleteFile else {
                        Log.error("Did not have version 0 of file!")
                        error = true
                        return
                    }
                    
                    let result = self.retry(request: {
                        self.add(fileIndex: fileIndex)
                    })
                    
                    switch result {
                    case .success:
                        break
                    case .deadlock, .error:
                        Log.error("Could not add new FileIndex!")
                        error = true
                        return
                    }
                }
            }
            
            numberTransferred += 1
        }
        
        if error {
            return .failure(failureResult)
        }
        
        if uploadSelect.forEachRowStatus == nil {
            return .success(numberUploadsTransferred: numberTransferred)
        }
        else {
            return .failure(nil)
        }
    }
    
    enum MarkDeletionCriteria {
        case userId(String)
        case sharingGroupUUID(String)
        
        func toString() -> String {
            switch self {
            case .userId(let userId):
                return "\(FileIndex.userIdKey)=\(userId)"
            case .sharingGroupUUID(let sharingGroupUUID):
                return "\(FileIndex.sharingGroupUUIDKey)='\(sharingGroupUUID)'"
            }
        }
    }
    
    // Returns nil on error; number of rows marked otherwise.
    // 8/5/20: Just added the "and \(FileIndex.deletedKey) = 0"-- which should ensure that the update can not occur twice, successfully, in a race.
    func markFilesAsDeleted(key:LookupKey) -> Int64? {
        let query = "UPDATE \(tableName) SET \(FileIndex.deletedKey)=1 WHERE " + lookupConstraint(key: key) + " and \(FileIndex.deletedKey) = 0"
        if db.query(statement: query) {
            let numberRows = db.numberAffectedRows()
            Log.debug("Number rows: \(numberRows) for query: \(query)")
            return numberRows
        }
        else {
            let error = db.error
            Log.error("Could not mark files as deleted in \(tableName): \(error)")
            return nil
        }
    }
    
    enum FileIndexResult {
    case fileIndex([FileInfo])
    case error(String)
    }
    
    // Does not return FileIndex rows where the user has been deleted and those rows have been marked as deleted.
    func fileIndex(forSharingGroupUUID sharingGroupUUID: String) -> FileIndexResult {
        let query = "select \(tableName).*, \(UserRepository.tableName).accountType from \(tableName), \(UserRepository.tableName) where sharingGroupUUID = '\(sharingGroupUUID)' and \(tableName).userId = \(UserRepository.tableName).userId"
        return fileIndex(forSelectQuery: query)
    }
    
    private func fileIndex(forSelectQuery selectQuery: String) -> FileIndexResult {
        guard let select = Select(db:db, query: selectQuery, modelInit: FileIndex.init, ignoreErrors:false) else {
            return .error("Failed on Select!")
        }
        
        var result:[FileInfo] = []
        var error:FileIndexResult!
        
        select.forEachRow { rowModel in
            if let _ = error {
                return
            }
            
            let rowModel = rowModel as! FileIndex

            let fileInfo = FileInfo()
            fileInfo.fileUUID = rowModel.fileUUID
            fileInfo.deviceUUID = rowModel.deviceUUID
            fileInfo.fileVersion = rowModel.fileVersion
            fileInfo.deleted = rowModel.deleted
            fileInfo.mimeType = rowModel.mimeType
            fileInfo.creationDate = rowModel.creationDate
            fileInfo.updateDate = rowModel.updateDate
            fileInfo.fileGroupUUID = rowModel.fileGroupUUID
            fileInfo.owningUserId = rowModel.userId
            fileInfo.sharingGroupUUID = rowModel.sharingGroupUUID
            fileInfo.objectType = rowModel.objectType
            fileInfo.changeResolverName = rowModel.changeResolverName
            fileInfo.appMetaData = rowModel.appMetaData
            fileInfo.fileLabel = rowModel.fileLabel
            
            guard let accountType = rowModel.accountType,
                let accountScheme = AccountScheme(.accountName(accountType)),
                let cloudStorageType = accountScheme.cloudStorageType else {
                    error = .error("Failed getting cloud storage type for fileUUID: \(String(describing: rowModel.fileUUID))")
                return
            }
            
            fileInfo.cloudStorageType = cloudStorageType

            result.append(fileInfo)
        }
        
        if let error = error {
            return error
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
        
        var query = "select \(tableName).*, \(UserRepository.tableName).accountType from \(tableName), \(UserRepository.tableName) where \(tableName).userId = \(UserRepository.tableName).userId and ( "
        
        var numberValues = 0
        for key in keys {
            if numberValues > 0 {
                query += " or "
            }
            
            query += " (\(lookupConstraint(key: key))) "
            
            numberValues += 1
        }
        
        query += " )"
        
        return fileIndex(forSelectQuery: query)
    }
    
    func getFileIndex(forFileUUID fileUUID: String, sharingGroupUUID: String) throws -> FileIndex {
        let key = Self.LookupKey.primaryKeys(sharingGroupUUID: sharingGroupUUID, fileUUID: fileUUID)
        let result = lookup(key: key, modelInit: FileIndex.init)
        guard case .found(let model) = result,
            let fileIndex = model as? FileIndex else {
            throw Errors.couldNotLookupFileUUID
        }
        
        return fileIndex
    }
}
