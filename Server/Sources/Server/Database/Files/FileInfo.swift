//
//  FileInfo.swift
//  Server
//
//  Created by Christopher Prince on 2/18/17.
//
//

import Foundation
import Gloss

#if SERVER
import Kitura
#endif

public class FileInfo : Encodable, Decodable, CustomStringConvertible, Filenaming {
    static let fileUUIDKey = "fileUUID"
    var fileUUID: String!
    
    static let deviceUUIDKey = "deviceUUID"
    var deviceUUID: String?
    
    static let creationDateKey = "creationDate"
    var creationDate: Date?
 
    static let updateDateKey = "updateDate"
    var updateDate: Date?
    
    static let cloudFolderNameKey = "cloudFolderName"
    var cloudFolderName: String?
    
    static let mimeTypeKey = "mimeType"
    var mimeType: String?
    
    static let appMetaDataKey = "appMetaData"
    var appMetaData: String?
    
    static let deletedKey = "deleted"
    var deleted:Bool! = false
    
    static let fileVersionKey = "fileVersion"
    var fileVersion: FileVersionInt!
    
    static let fileSizeBytesKey = "fileSizeBytes"
    var fileSizeBytes: Int64!
    
    public var description: String {
        return "fileUUID: \(fileUUID); deviceUUID: \(String(describing: deviceUUID)); creationDate: \(String(describing: creationDate)); updateDate: \(String(describing: updateDate)); mimeTypeKey: \(String(describing: mimeType)); appMetaData: \(String(describing: appMetaData)); deleted: \(deleted); fileVersion: \(fileVersion); fileSizeBytes: \(fileSizeBytes); cloudFolderName: \(String(describing: cloudFolderName))"
    }
    
    required public init?(json: JSON) {
        self.fileUUID = FileInfo.fileUUIDKey <~~ json
        self.deviceUUID = FileInfo.deviceUUIDKey <~~ json
        self.mimeType = FileInfo.mimeTypeKey <~~ json
        self.appMetaData = FileInfo.appMetaDataKey <~~ json
        self.deleted = FileInfo.deletedKey <~~ json
        
        self.fileVersion = Decoder.decode(int32ForKey: FileInfo.fileVersionKey)(json)
        self.fileSizeBytes = Decoder.decode(int64ForKey: FileInfo.fileSizeBytesKey)(json)
        
        self.cloudFolderName = FileInfo.cloudFolderNameKey <~~ json
        
        let dateFormatter = DateExtras.getDateFormatter(format: .DATETIME)
        self.creationDate = Decoder.decode(dateForKey: FileInfo.creationDateKey, dateFormatter: dateFormatter)(json)
        self.updateDate = Decoder.decode(dateForKey: FileInfo.updateDateKey, dateFormatter: dateFormatter)(json)
    }
    
    convenience init?() {
        self.init(json:[:])
    }
    
    public func toJSON() -> JSON? {
        let dateFormatter = DateExtras.getDateFormatter(format: .DATETIME)

        return jsonify([
            FileInfo.fileUUIDKey ~~> self.fileUUID,
            FileInfo.deviceUUIDKey ~~> self.deviceUUID,
            FileInfo.mimeTypeKey ~~> self.mimeType,
            FileInfo.appMetaDataKey ~~> self.appMetaData,
            FileInfo.deletedKey ~~> self.deleted,
            FileInfo.fileVersionKey ~~> self.fileVersion,
            FileInfo.fileSizeBytesKey ~~> self.fileSizeBytes,
            FileInfo.cloudFolderNameKey ~~> self.cloudFolderName,
            Encoder.encode(dateForKey: FileInfo.creationDateKey, dateFormatter: dateFormatter)(self.creationDate),
            Encoder.encode(dateForKey: FileInfo.updateDateKey, dateFormatter: dateFormatter)(self.updateDate)
        ])
    }
}

