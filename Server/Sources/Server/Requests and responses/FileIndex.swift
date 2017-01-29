//
//  FileIndex.swift
//  Server
//
//  Created by Christopher Prince on 1/28/17.
//
//

import Foundation
import PerfectLib
import Gloss
import Kitura

// Request an index of all files owned by the user-- queries the meta data on the sync server.

class FileIndexRequest : NSObject, RequestMessage {
    // MARK: Properties for use in request message.
    
    static let deviceUUIDKey = "deviceUUID"
    var deviceUUID:String!
    
    func nonNilKeys() -> [String] {
        return [FileIndexRequest.deviceUUIDKey]
    }
    
    func allKeys() -> [String] {
        return self.nonNilKeys()
    }
    
    required init?(json: JSON) {
        super.init()
        
        self.deviceUUID = FileIndexRequest.deviceUUIDKey <~~ json

        if !self.propertiesHaveValues(propertyNames: self.nonNilKeys()) {
            return nil
        }
    }
    
    required convenience init?(request: RouterRequest) {
        self.init(json: request.queryParameters)
    }
    
    func toJSON() -> JSON? {
        return jsonify([
            FileIndexRequest.deviceUUIDKey ~~> self.deviceUUID
        ])
    }
}

class FileIndexResponse : ResponseMessage {
    class FileInfo : Encodable, Decodable, CustomStringConvertible {
        static let fileUUIDKey = "fileUUID"
        var fileUUID: String!
        
        static let mimeTypeKey = "mimeType"
        var mimeType: String!
        
        static let appMetaDataKey = "appMetaData"
        var appMetaData: String?
        
        static let deletedKey = "deleted"
        var deleted:Bool!
        
        static let fileVersionKey = "fileVersion"
        var fileVersion: FileVersionInt!
        
        static let fileSizeBytesKey = "fileSizeBytes"
        var fileSizeBytes: Int64!
        
        public var description: String {
            return "fileUUID: \(fileUUID!); mimeTypeKey: \(mimeType!); appMetaData: \(appMetaData); deleted: \(deleted!); fileVersion: \(fileVersion!); fileSizeBytes: \(fileSizeBytes!)"
        }
        
        required init?(json: JSON) {
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
        
        func toJSON() -> JSON? {
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

    // TODO: Need to remove these across all response messages. I'm not using this.
    static let resultKey = "result"
    var result: PerfectLib.JSONConvertible?
    
    static let masterVersionKey = "masterVersion"
    var masterVersion:MasterVersionInt!
    
    static let fileIndexKey = "fileIndex"
    var fileIndex:[FileInfo]?
    
    required init?(json: JSON) {
        self.masterVersion = FileIndexResponse.masterVersionKey <~~ json
        self.fileIndex = FileIndexResponse.fileIndexKey <~~ json
    }
    
    convenience init?() {
        self.init(json:[:])
    }
    
    // MARK: - Serialization
    func toJSON() -> JSON? {
        return jsonify([
            FileIndexResponse.masterVersionKey ~~> self.masterVersion,
            FileIndexResponse.fileIndexKey ~~> self.fileIndex
        ])
    }
}
