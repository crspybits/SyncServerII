
// A log of pending upload requests.

import Foundation
import ServerShared
import LoggerAPI

class UploadRequestLog : NSObject, Model {
    static let userIdKey = "userId"
    var userId: UserId!
    
    static let sharingGroupUUIDKey = "sharingGroupUUID"
    var sharingGroupUUID: String!

    static let deviceUUIDKey = "deviceUUID"
    var deviceUUID: String!
    
    static let fileUUIDKey = "fileUUID"
    var fileUUID: String!
    
    // The contents of the upload request.
    static let uploadContentsKey = "uploadContents"
    var uploadContents: String!

    // Initially set to false. Set to true when DoneUploads called.
    static let committedKey = "committed"
    var committed: Bool!
    
    subscript(key:String) -> Any? {
        set {
            switch key {
            case Self.userIdKey:
                userId = newValue as? UserId
                
            case Self.sharingGroupUUIDKey:
                sharingGroupUUID = newValue as? String
                
            case Self.deviceUUIDKey:
                deviceUUID = newValue as? String

            case Self.fileUUIDKey:
                fileUUID = newValue as? String

            case Self.uploadContentsKey:
                uploadContents = newValue as? String

            case Self.committedKey:
                committed = newValue as? Bool
                
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
            case Self.committedKey:
                return {(x:Any) -> Any? in
                    return (x as! Int8) == 1
                }
            
            default:
                return nil
        }
    }
}

class UploadRequestLogRepository : Repository, RepositoryLookup {
    private(set) var db:Database!

    required init(_ db:Database) {
        self.db = db
    }
    
    var tableName:String {
        return UploadRequestLogRepository.tableName
    }
    
    static var tableName:String {
        return "UploadRequestLog"
    }
    
    func upcreate() -> Database.TableUpcreateResult {
        let createColumns =
            "(userId BIGINT NOT NULL, " +
            
            "sharingGroupUUID VARCHAR(\(Database.uuidLength)) NOT NULL, " +

            "deviceUUID VARCHAR(\(Database.uuidLength)) NOT NULL, " +

            "fileUUID VARCHAR(\(Database.uuidLength)) NOT NULL, " +
            
            "uploadContents BLOB NOT NULL, " +

            "committed BOOL NOT NULL, " +
            
            // Not including fileVersion in the key because I don't want to allow the possiblity of uploading vN of a file and vM of a file at the same time.
            // This allows for the possibility of a client interleaving uploads to different sharing group UUID's (without interveneing DoneUploads) -- because the same fileUUID cannot appear in different sharing groups.
            "UNIQUE (fileUUID, deviceUUID))"
        
        return db.createTableIfNeeded(tableName: "\(tableName)", columnCreateQuery: createColumns)
    }
    
    enum LookupKey : CustomStringConvertible {
        case primaryKeys(fileUUID: String, deviceUUID: String)
        
        var description : String {
            switch self {
            case .primaryKeys(let fileUUID, let deviceUUID):
                return "fileUUID(\(fileUUID), deviceUUID(\(deviceUUID))"
            }
        }
    }
    
    // Returns a constraint for a WHERE clause in mySQL based on the key
    func lookupConstraint(key:LookupKey) -> String {
        switch key {
        case .primaryKeys(let fileUUID, let deviceUUID):
            return "fileUUID = '\(fileUUID)' and deviceUUID = '\(deviceUUID)'"
        }
    }
    
    enum AddResult {
        case success
        case error(String)
    }
    
    func add(request:UploadRequestLog) -> AddResult {
        guard let fileUUID = request.fileUUID,
            let userId = request.userId,
            let sharingGroupUUID = request.sharingGroupUUID,
            let deviceUUID = request.deviceUUID,
            let contents = request.uploadContents else {
            return .error("Null field while attempting to add: \(request)")
        }
        
        let insert = Database.PreparedStatement(repo: self, type: .insert)

        insert.add(fieldName: UploadRequestLog.fileUUIDKey, value: .string(fileUUID))
        insert.add(fieldName: UploadRequestLog.userIdKey, value: .int64(userId))
        insert.add(fieldName: UploadRequestLog.sharingGroupUUIDKey, value: .string(sharingGroupUUID))
        insert.add(fieldName: UploadRequestLog.deviceUUIDKey, value: .string(deviceUUID))
        insert.add(fieldName: UploadRequestLog.uploadContentsKey, value: .string(contents))
        insert.add(fieldName: UploadRequestLog.committedKey, value: .bool(false))
        
        do {
            try insert.run()
            Log.info("Sucessfully created UploadRequestLog row")
            return .success
        }
        catch (let error) {
            Log.error("Could not insert into \(tableName): \(error)")
            return .error("\(error)")
        }
    }
    
    func update() {
    }
}


