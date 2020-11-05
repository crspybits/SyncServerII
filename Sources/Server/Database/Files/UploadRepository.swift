//
//  UploadRepository.swift
//  Server
//
//  Created by Christopher Prince on 1/16/17.
//
//

// Persistent Storage for temporarily storing general meta data for file uploads and file deletions before finally storing that info in the FileIndex.

/* 7/19/20; This now represents these kinds of events:
    1) entire v0 file uploads,
    2) vN file change uploads, and
    3) single file deletion (files with no file group)
    4) deletion of all files in a file group.
    
    Because of the addition of change uploads, the prior index: "UNIQUE (fileUUID, userId, deviceUUID)" has been removed. This is because the same user/device may upload multiple changes to the same file before they are applied to the file-- which is is done asynchronously to client requests.
    
    TODO: I'm going to removing upload undeletion, and app meta data upload for all but v0 file uploads.
*/

import Foundation
import ServerShared
import LoggerAPI
import ChangeResolvers

// `public` only because of some problems I was having with testing.
public enum UploadState : String {
    case v0UploadCompleteFile
    case vNUploadFileChange
    case deleteSingleFile
    // deletion of a file group will not be represented by an Upload row, but by a DeferredUpload row (only).
    
    // DEPRECATED.
    case uploadingUndelete
    case uploadedUndelete
    
    var isUploadFile: Bool {
        return self == .v0UploadCompleteFile || self == .vNUploadFileChange
    }

    static func maxCharacterLength() -> Int { return 22 }
}

class Upload : NSObject, Model, ChangeResolverContents {
    required override init() {
        super.init()
    }

    static let uploadIdKey = "uploadId"
    var uploadId: Int64!
    
    static let fileUUIDKey = "fileUUID"
    var fileUUID: String!
    
    static let userIdKey = "userId"
    // The userId of the uploading user. i.e., this is not necessarily the owning user id.
    var userId: UserId!
    
    // On initial client request, this is for upload deletion. For file uploads, this is used when file versions > v0 but only *after* the initial client request.
    static let fileVersionKey = "fileVersion"
    var fileVersion: FileVersionInt!
    
    static let deferredUploadIdKey = "deferredUploadId"
    // Reference to the DeferredUpload table for vN uploads.
    var deferredUploadId: Int64?
    
    static let deviceUUIDKey = "deviceUUID"
    var deviceUUID: String!
    
    static let fileGroupUUIDKey = "fileGroupUUID"
    // Not all files have to be associated with a file group.
    var fileGroupUUID:String?
    
    static let objectTypeKey = "objectType"
    // Not all files have to be associated with a file group, and thus not all files have a objectType.
    var objectType:String?
    
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
    
    // Can be non-nil for v0 files only. Leave nil if files are static and changes cannot be applied.
    static let changeResolverNameKey = "changeResolverName"
    var changeResolverName: String?
    
    // The contents of the upload for file uploads, for files with changeResolverName's and file versions > 0.
    static let uploadContentsKey = "uploadContents"
    var uploadContents: Data?
    
    // This is not present in upload deletions.
    static let mimeTypeKey = "mimeType"
    var mimeType: String?
    
    // Required only when the state is .uploaded
    static let lastUploadedCheckSumKey = "lastUploadedCheckSum"
    var lastUploadedCheckSum: String?
    
    // These two values are a replacement for the prior DoneUploads explicit endpoint. Think of them as marking an upload with "uploadIndex of uploadCount". E.g., suppose there are three uploads in a batch. Then three entries in the Upload table (1 of 3, 2 of 3, and 3 of 3) will mark the trigger for DoneUploads.
    static let uploadIndexKey = "uploadIndex"
    var uploadIndex: Int32!
    static let uploadCountKey = "uploadCount"
    var uploadCount: Int32!
    
    static let fileLabelKey = "fileLabel"
    var fileLabel: String?
    
    subscript(key:String) -> Any? {
        set {
            switch key {
            case Upload.uploadIdKey:
                uploadId = newValue as! Int64?

            case Upload.fileUUIDKey:
                fileUUID = newValue as! String?
                
            case Upload.fileGroupUUIDKey:
                fileGroupUUID = newValue as! String?
                
            case Upload.objectTypeKey:
                objectType = newValue as? String

            case Upload.sharingGroupUUIDKey:
                sharingGroupUUID = newValue as! String?

            case Upload.userIdKey:
                userId = newValue as! UserId?
                
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
                
            case Upload.mimeTypeKey:
                mimeType = newValue as! String?
                
            case Upload.lastUploadedCheckSumKey:
                lastUploadedCheckSum = newValue as! String?
                
            case Upload.uploadContentsKey:
                uploadContents = newValue as? Data
                
            case Upload.changeResolverNameKey:
                changeResolverName = newValue as? String
                
            case Upload.uploadIndexKey:
                uploadIndex = newValue as? Int32
                
            case Upload.uploadCountKey:
                uploadCount = newValue as? Int32
                
            case Upload.fileVersionKey:
                fileVersion = newValue as? FileVersionInt
                
            case Upload.deferredUploadIdKey:
                deferredUploadId = newValue as? Int64

            case Upload.fileLabelKey:
                fileLabel = newValue as? String
                
            default:
                Log.error("key: \(key)")
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
                
            case Upload.uploadContentsKey:
                return {(x:Any) -> Any? in
                    guard let x = x as? Array<UInt8> else {
                        return nil
                    }
                    return Data(x)
                }
            
            default:
                return nil
        }
    }
}

class UploadRepository : Repository, RepositoryLookup, ModelIndexId {
    static let indexIdKey = Upload.uploadIdKey
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
    
    static let uniqueFileLabelConstraintName = "UniqueFileLabel"
    static let uniqueFileLabelConstraint = "UNIQUE (fileGroupUUID, fileLabel)"
    
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
            
            "objectType VARCHAR(\(FileGroup.maxLengthObjectTypeName)), " +

            "sharingGroupUUID VARCHAR(\(Database.uuidLength)) NOT NULL, " +
            
            // Not saying "NOT NULL" here only because in the first deployed version of the database, I didn't have these dates. Plus, upload deletions need not have dates. And when uploading a new version of a file we won't give the creationDate.
            "creationDate DATETIME," +
            "updateDate DATETIME," +
                
            // MIME type of the file; will be nil for UploadDeletion's.
            "mimeType VARCHAR(\(Database.maxMimeTypeLength)), " +

            // Optional app-specific meta data
            "appMetaData TEXT, " +
            
            // 3/25/18; This used to be `NOT NULL` but now allowing it to be NULL because when we upload an app meta data change, it will be null.
            // 7/10/20: And will be nil for file uploads too.
            "fileVersion INT, " +
            
            // Making this optional because appMetaData is optional. If there is app meta data, this must not be null.
            "appMetaDataVersion INT, " +
            
            // Nullable because v0 uploads will not have this.
            // 16MB limit on size. See https://stackoverflow.com/questions/5775571 and
            "uploadContents MEDIUMBLOB, " +
            
            "uploadIndex INT NOT NULL, " +
            
            "uploadCount INT NOT NULL, " +
            
            // true if file upload is version v0, false if upload is vN, N > 0.
            // nil if this is an upload deletion.
            "v0UploadFileVersion BOOL, " +
            
            // Non-nil for vN file uploads when they have been sent for deferred uploading.
            "deferredUploadId BIGINT, " +
            
            // 11/3/20; Optional only because earlier files will not have a fileLabel.
            "fileLabel VARCHAR(\(FileLabel.maxLength)), " +
            
            "changeResolverName VARCHAR(\(ChangeResolverConstants.maxChangeResolverNameLength)), " +

            "state VARCHAR(\(UploadState.maxCharacterLength())) NOT NULL, " +

            // Can be null if we create the Upload entry before actually uploading the file.
            "lastUploadedCheckSum TEXT, " +
            
            "FOREIGN KEY (sharingGroupUUID) REFERENCES \(SharingGroupRepository.tableName)(\(SharingGroup.sharingGroupUUIDKey)), " +
            
            // Because file label's must be unique within file group's.
            "CONSTRAINT \(Self.uniqueFileLabelConstraintName) \(Self.uniqueFileLabelConstraint), " +

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
            
            if db.columnExists(Upload.fileGroupUUIDKey, in: tableName) == false {
                if !db.addColumn("\(Upload.fileGroupUUIDKey) VARCHAR(\(Database.uuidLength))", to: tableName) {
                    return .failure(.columnCreation)
                }
            }
            
            // 7/4/20; Evolution 4
            
            if db.columnExists(Upload.uploadContentsKey, in: tableName) == false {
                if !db.addColumn("\(Upload.uploadContentsKey) MEDIUMBLOB", to: tableName) {
                    return .failure(.columnCreation)
                }
            }
            
            if db.columnExists(Upload.uploadIndexKey, in: tableName) == false {
                if !db.addColumn("\(Upload.uploadIndexKey) INT NOT NULL", to: tableName) {
                    return .failure(.columnCreation)
                }
            }
            
            if db.columnExists(Upload.uploadCountKey, in: tableName) == false {
                if !db.addColumn("\(Upload.uploadCountKey) INT NOT NULL", to: tableName) {
                    return .failure(.columnCreation)
                }
            }
            
            if db.columnExists(Upload.deferredUploadIdKey, in: tableName) == false {
                if !db.addColumn("\(Upload.deferredUploadIdKey) BIGINT", to: tableName) {
                    return .failure(.columnCreation)
                }
            }
            
            if db.columnExists(Upload.changeResolverNameKey, in: tableName) == false {
                if !db.addColumn("\(Upload.changeResolverNameKey) VARCHAR(\(ChangeResolverConstants.maxChangeResolverNameLength))", to: tableName) {
                    return .failure(.columnCreation)
                }
            }
            
            if db.columnExists(Upload.objectTypeKey, in: tableName) == false {
                if !db.addColumn("\(Upload.objectTypeKey) VARCHAR(\(FileGroup.maxLengthObjectTypeName))", to: tableName) {
                    return .failure(.columnCreation)
                }
            }

            if db.columnExists(Upload.fileLabelKey, in: tableName) == false {
                if !db.addColumn("\(Upload.fileLabelKey) VARCHAR(\(FileLabel.maxLength))", to: tableName) {
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
    
    private func basicFieldCheck(upload:Upload, fileInFileIndex: Bool) -> Bool {
        // Basic criteria-- applies across uploads and upload deletion.
        if upload.deviceUUID == nil || upload.fileUUID == nil || upload.userId == nil || upload.state == nil || upload.sharingGroupUUID == nil ||
            upload.uploadCount == nil || upload.uploadIndex == nil {
            Log.error("deviceUUID group nil")
            return true
        }
        
        if upload.changeResolverName != nil && upload.state != .v0UploadCompleteFile {
            Log.error("changeResolverName can only be non-nil with a v0 upload.")
            return true
        }
        
        if upload.state.isUploadFile && upload.updateDate == nil {
            Log.error("Uploading a file and the updateDate is nil")
            return true
        }
        
        if upload.state.isUploadFile && !fileInFileIndex && upload.creationDate == nil {
            Log.error("Must have a creationDate when an uploaded file is not in the index.")
            return true
        }
        
        if upload.state.isUploadFile && upload.lastUploadedCheckSum == nil && upload.state == .v0UploadCompleteFile {
            Log.error("Need lastUploadedCheckSum for v0 uploads.")
            return true
        }
        
        return false
    }
    
    enum AddResult: RetryRequest {
        case success(uploadId:Int64)
        case duplicateEntry
        case aModelValueWasNil
        case otherError(String)
        
        case deadlock
        case waitTimeout
        
        var shouldRetry: Bool {
            if case .deadlock = self {
                return true
            }
            if case .waitTimeout = self {
                return true
            }
            else {
                return false
            }
        }
    }
    
    // uploadId in the model is ignored and the automatically generated uploadId is returned if the add is successful. On success, the upload record is modified with this uploadId.
    func add(upload:Upload, fileInFileIndex:Bool=false) -> AddResult {
        if basicFieldCheck(upload: upload, fileInFileIndex:fileInFileIndex) {
            Log.error("One of the model values was nil!")
            return .aModelValueWasNil
        }
        
        let insert = Database.PreparedStatement(repo: self, type: .insert)
        
        insert.add(fieldName: Upload.fileUUIDKey, value: .stringOptional(upload.fileUUID))
        insert.add(fieldName: Upload.userIdKey, value: .int64Optional(upload.userId))
        insert.add(fieldName: Upload.deviceUUIDKey, value: .stringOptional(upload.deviceUUID))
        insert.add(fieldName: Upload.stateKey, value: .stringOptional(upload.state?.rawValue))
        insert.add(fieldName: Upload.sharingGroupUUIDKey, value: .stringOptional(upload.sharingGroupUUID))

        insert.add(fieldName: Upload.appMetaDataKey, value: .stringOptional(upload.appMetaData))
        
        insert.add(fieldName: Upload.fileGroupUUIDKey, value: .stringOptional(upload.fileGroupUUID))
        insert.add(fieldName: Upload.objectTypeKey, value: .stringOptional(upload.objectType))
        
        insert.add(fieldName: Upload.lastUploadedCheckSumKey, value: .stringOptional(upload.lastUploadedCheckSum))
        insert.add(fieldName: Upload.mimeTypeKey, value: .stringOptional(upload.mimeType))

        if let date = upload.creationDate {
            let creationDateValue = DateExtras.date(date, toFormat: .DATETIME)
            insert.add(fieldName: Upload.creationDateKey, value: .string(creationDateValue))
        }

        if let date = upload.updateDate {
            let updateDateValue = DateExtras.date(date, toFormat: .DATETIME)
            Log.debug("upload.updateDate: \(String(describing: upload.updateDate))")
            Log.debug("updateDateValue: \(updateDateValue)")
            insert.add(fieldName: Upload.updateDateKey, value: .string(updateDateValue))
        }

        insert.add(fieldName: Upload.fileVersionKey, value: .int32Optional(upload.fileVersion))
        insert.add(fieldName: Upload.uploadContentsKey, value: .dataOptional(upload.uploadContents))
        insert.add(fieldName: Upload.uploadIndexKey, value: .int32Optional(upload.uploadIndex))
        insert.add(fieldName: Upload.uploadCountKey, value: .int32Optional(upload.uploadCount))
        insert.add(fieldName: Upload.changeResolverNameKey, value: .stringOptional(upload.changeResolverName))
        
        insert.add(fieldName: Upload.deferredUploadIdKey, value: .int64Optional(upload.deferredUploadId))
        
        insert.add(fieldName: Upload.fileLabelKey, value: .stringOptional(upload.fileLabel))

        do {
            try insert.run()
            Log.info("Sucessfully created Upload row")
            let uploadId = db.lastInsertId()
            upload.uploadId = uploadId
            return .success(uploadId: uploadId)
        }
        catch (let error) {
            Log.info("Failed inserting Upload row: \(db.errorCode()); \(db.errorMessage())")
            
            if db.errorCode() == Database.deadlockError {
                return .deadlock
            }
            else if db.errorCode() == Database.lockWaitTimeout {
                return .waitTimeout
            }
            else if db.errorCode() == Database.duplicateEntryForKey {
                return .duplicateEntry
            }
            else {
                let message = "Could not insert into \(tableName): \(error)"
                Log.error(message)
                return .otherError(message)
            }
        }
    }
    
    // The Upload model *must* have an uploadId
    func update(upload:Upload, fileInFileIndex:Bool=false) -> Bool {
        if upload.uploadId == nil || basicFieldCheck(upload: upload, fileInFileIndex:fileInFileIndex) {
            Log.error("One of the model values was nil!")
            return false
        }
    
        // TODO: *2* Seems like we could use an encoding here to deal with sql injection issues.
        let appMetaDataField = getUpdateFieldSetter(fieldValue: upload.appMetaData, fieldName: Upload.appMetaDataKey)
        
        let lastUploadedCheckSumField = getUpdateFieldSetter(fieldValue: upload.lastUploadedCheckSum, fieldName: Upload.lastUploadedCheckSumKey)
        
        let mimeTypeField = getUpdateFieldSetter(fieldValue: upload.mimeType, fieldName: Upload.mimeTypeKey)
        
        let fileGroupUUIDField = getUpdateFieldSetter(fieldValue: upload.fileGroupUUID, fieldName: Upload.fileGroupUUIDKey)
        let objectTypeField = getUpdateFieldSetter(fieldValue: upload.objectType, fieldName: Upload.objectTypeKey)
        
        let deferredUploadIdField = getUpdateFieldSetter(fieldValue: upload.deferredUploadId, fieldName: Upload.deferredUploadIdKey, fieldIsString: false)
        
        let fileVersionField = getUpdateFieldSetter(fieldValue: upload.fileVersion, fieldName: Upload.fileVersionKey, fieldIsString: false)
        
        let changeResolverNameField = getUpdateFieldSetter(fieldValue: upload.changeResolverName, fieldName: Upload.changeResolverNameKey)
        
        let query = "UPDATE \(tableName) SET fileUUID='\(upload.fileUUID!)', userId=\(upload.userId!), state='\(upload.state!.rawValue)', deviceUUID='\(upload.deviceUUID!)' \(lastUploadedCheckSumField) \(appMetaDataField) \(mimeTypeField) \(fileGroupUUIDField) \(deferredUploadIdField) \(fileVersionField) \(changeResolverNameField) \(objectTypeField) WHERE uploadId=\(upload.uploadId!)"
        
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
        case uploadId(Int64)
        case fileUUID(String)
        case userId(UserId)
        case filesForUserDevice(userId:UserId, deviceUUID:String, sharingGroupUUID: String)
        case primaryKey(fileUUID:String, userId:UserId, deviceUUID:String)
        case fileGroupUUIDWithState(fileGroupUUID: String, state: UploadState)
        case fileUUIDWithState(fileUUID: String, state: UploadState)
        case deferredUploadId(Int64)
        case fileGroupUUIDAndFileLabel(fileGroupUUID: String, fileLabel: String)
        
        var description : String {
            switch self {
            case .uploadId(let uploadId):
                return "uploadId(\(uploadId))"
            case .deferredUploadId(let deferredUploadId):
                return "deferredUploadId(\(deferredUploadId))"
            case .fileUUID(let fileUUID):
                return "fileUUID(\(fileUUID))"
            case .userId(let userId):
                return "userId(\(userId))"
            case .filesForUserDevice(let userId, let deviceUUID, let sharingGroupUUID):
                return "userId(\(userId)); deviceUUID(\(deviceUUID)); sharingGroupUUID(\(sharingGroupUUID))"
            case .primaryKey(let fileUUID, let userId, let deviceUUID):
                return "fileUUID(\(fileUUID)); userId(\(userId)); deviceUUID(\(deviceUUID))"
            case .fileGroupUUIDWithState(let fileGroupUUID, let state):
                return "fileGroupUUID(\(fileGroupUUID); state: \(state.rawValue))"
            case .fileUUIDWithState(let fileUUID, let state):
                return "fileUUID(\(fileUUID); state: \(state.rawValue))"
            case .fileGroupUUIDAndFileLabel(let fileGroupUUID, let fileLabel):
                return "fileGroupUUID(\(fileGroupUUID); fileLabel: \(fileLabel))"
            }
        }
    }
    
    func lookupConstraint(key:LookupKey) -> String {
        switch key {
        case .uploadId(let uploadId):
            return "uploadId = '\(uploadId)'"
        case .deferredUploadId(let deferredUploadId):
            return "deferredUploadId = \(deferredUploadId)"
        case .fileUUID(let fileUUID):
            return "fileUUID = '\(fileUUID)'"
        case .userId(let userId):
            return "userId = '\(userId)'"
        case .filesForUserDevice(let userId, let deviceUUID, let sharingGroupUUID):
            return "userId = \(userId) and deviceUUID = '\(deviceUUID)' and sharingGroupUUID = '\(sharingGroupUUID)'"
        case .primaryKey(let fileUUID, let userId, let deviceUUID):
            return "fileUUID = '\(fileUUID)' and userId = \(userId) and deviceUUID = '\(deviceUUID)'"
        case .fileGroupUUIDWithState(let fileGroupUUID, let state):
            return "fileGroupUUID = '\(fileGroupUUID)' and state = '\(state.rawValue)'"
        case .fileUUIDWithState(let fileUUID, let state):
            return "fileUUID = '\(fileUUID)' and state = '\(state.rawValue)'"
        case .fileGroupUUIDAndFileLabel(let fileGroupUUID, let fileLabel):
            return "fileGroupUUID = '\(fileGroupUUID)' and fileLabel = '\(fileLabel)'"
        }
    }
    
    func select(forUserId userId: UserId, sharingGroupUUID: String, deviceUUID:String, deferredUploadIdNull: Bool = false, andState state:UploadState? = nil, forUpdate: Bool = false) -> Select? {
    
        var query = "select * from \(tableName) where userId=\(userId) and sharingGroupUUID = '\(sharingGroupUUID)' and deviceUUID='\(deviceUUID)'"
        
        if state != nil {
            query += " and state='\(state!.rawValue)'"
        }
        
        if deferredUploadIdNull {
            query += " and deferredUploadId IS NULL"
        }
        
        if forUpdate {
            query += " FOR UPDATE"
        }
        
        return Select(db:db, query: query, modelInit: Upload.init, ignoreErrors:false)
    }
    
    enum UploadedFilesResult {
        case uploads([Upload])
        case error(Swift.Error?)
    }
    
    // With nil `andState` parameter value, returns both file uploads and upload deletions.
    // Uploads are identified by userId, not effectiveOwningUserId: We want to organize uploads by specific user.
    // Set deferredUploadIdNil to true if you only want records where deferredUploadIdNil is non-nil.
    func uploadedFiles(forUserId userId: UserId, sharingGroupUUID: String, deviceUUID: String, deferredUploadIdNull: Bool = false, andState state:UploadState? = nil, forUpdate: Bool = false) -> UploadedFilesResult {
        
        guard let selectUploadedFiles = select(forUserId: userId, sharingGroupUUID: sharingGroupUUID, deviceUUID: deviceUUID, deferredUploadIdNull: deferredUploadIdNull, andState: state, forUpdate: forUpdate) else {
            return .error(nil)
        }

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
            let fileInfo = FileInfo()
            
            fileInfo.fileUUID = upload.fileUUID
            fileInfo.fileVersion = upload.fileVersion
            fileInfo.deleted = upload.state == .deleteSingleFile
            fileInfo.mimeType = upload.mimeType
            fileInfo.creationDate = upload.creationDate
            fileInfo.updateDate = upload.updateDate
            fileInfo.fileGroupUUID = upload.fileGroupUUID
            fileInfo.sharingGroupUUID = upload.sharingGroupUUID
            fileInfo.objectType = upload.objectType
            fileInfo.fileLabel = upload.fileLabel

            result += [fileInfo]
        }
        
        return result
    }
    
    // Return nil on an error. If somehow, no ids match, an empty array is returned.
    func select(forDeferredUploadIds deferredUploadIds: [Int64]) -> [Upload]? {
        guard deferredUploadIds.count > 0 else {
            Log.error("No upload ids given")
            return nil
        }
        
        let quotedIdsString = deferredUploadIds.map {String($0)}.map {"'\($0)'"}.joined(separator: ",")
    
        let query = "SELECT * FROM \(tableName) WHERE deferredUploadId IN (\(quotedIdsString))"
        
        guard let select = Select(db:db, query: query, modelInit: Upload.init, ignoreErrors:false) else {
            return nil
        }
        
        var result = [Upload]()
        var error = false
        select.forEachRow { model in
            guard !error, let model = model as? Upload else {
                error = true
                return
            }
            
            result += [model]
        }
        
        guard !error, select.forEachRowStatus == nil else {
            return nil
        }
        
        return result
    }
}
