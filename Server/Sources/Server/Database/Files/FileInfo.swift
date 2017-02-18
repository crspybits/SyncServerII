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

public class FileInfo : Encodable, Decodable, CustomStringConvertible {
    static let fileUUIDKey = "fileUUID"
    var fileUUID: String!
    
    static let mimeTypeKey = "mimeType"
    var mimeType: String!
    
    static let appMetaDataKey = "appMetaData"
    var appMetaData: String?
    
    static let deletedKey = "deleted"
    var deleted:Bool! = false
    
    static let fileVersionKey = "fileVersion"
    var fileVersion: FileVersionInt!
    
    static let fileSizeBytesKey = "fileSizeBytes"
    var fileSizeBytes: Int64!
    
    public var description: String {
        return "fileUUID: \(fileUUID!); mimeTypeKey: \(mimeType!); appMetaData: \(appMetaData); deleted: \(deleted!); fileVersion: \(fileVersion!); fileSizeBytes: \(fileSizeBytes!)"
    }
    
    required public init?(json: JSON) {
        self.fileUUID = FileInfo.fileUUIDKey <~~ json
        self.mimeType = FileInfo.mimeTypeKey <~~ json
        self.appMetaData = FileInfo.appMetaDataKey <~~ json
        self.deleted = FileInfo.deletedKey <~~ json
        self.fileVersion = FileInfo.fileVersionKey <~~ json
        self.fileSizeBytes = FileInfo.fileSizeBytesKey <~~ json
    }
    
    convenience init?() {
        self.init(json:[:])
    }
    
    public func toJSON() -> JSON? {
        return jsonify([
            FileInfo.fileUUIDKey ~~> self.fileUUID,
            FileInfo.mimeTypeKey ~~> self.mimeType,
            FileInfo.appMetaDataKey ~~> self.appMetaData,
            FileInfo.deletedKey ~~> self.deleted,
            FileInfo.fileVersionKey ~~> self.fileVersion,
            FileInfo.fileSizeBytesKey ~~> self.fileSizeBytes
        ])
    }
}

