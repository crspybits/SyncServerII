//
//  DownloadFile.swift
//  Server
//
//  Created by Christopher Prince on 1/29/17.
//
//

import Foundation
import Gloss

#if SERVER
import Kitura
#endif

class DownloadFileRequest : NSObject, RequestMessage {
    // MARK: Properties for use in request message.
    
    static let fileUUIDKey = "fileUUID"
    var fileUUID:String!
    
    static let deviceUUIDKey = "deviceUUID"
    var deviceUUID:String!
    
    // A root-level folder in the cloud file service.
    static let cloudFolderNameKey = "cloudFolderName"
    var cloudFolderName:String!
    
    // This must indicate the current version of the file in the FileIndex.
    static let fileVersionKey = "fileVersion"
    var fileVersion:FileVersionInt!
    
    // Overall version for files for the specific user; assigned by the server.
    static let masterVersionKey = "masterVersion"
    var masterVersion:MasterVersionInt!
    
    func nonNilKeys() -> [String] {
        return [DownloadFileRequest.fileUUIDKey, DownloadFileRequest.deviceUUIDKey, DownloadFileRequest.cloudFolderNameKey, DownloadFileRequest.fileVersionKey, DownloadFileRequest.masterVersionKey]
    }
    
    func allKeys() -> [String] {
        return self.nonNilKeys()
    }
    
    required init?(json: JSON) {
        super.init()
        
        self.fileUUID = DownloadFileRequest.fileUUIDKey <~~ json
        self.deviceUUID = DownloadFileRequest.deviceUUIDKey <~~ json
        self.masterVersion = DownloadFileRequest.masterVersionKey <~~ json
        self.fileVersion = DownloadFileRequest.fileVersionKey <~~ json
        self.cloudFolderName = DownloadFileRequest.cloudFolderNameKey <~~ json
        
        if !self.propertiesHaveValues(propertyNames: self.nonNilKeys()) {
            return nil
        }
        
        guard let _ = NSUUID(uuidString: self.fileUUID),
            let _ = NSUUID(uuidString: self.deviceUUID) else {
            return nil
        }
    }
    
#if SERVER
    required convenience init?(request: RouterRequest) {
        self.init(json: request.queryParameters)
    }
#endif
    
    func toJSON() -> JSON? {
        return jsonify([
            DownloadFileRequest.fileUUIDKey ~~> self.fileUUID,
            DownloadFileRequest.deviceUUIDKey ~~> self.deviceUUID,
            DownloadFileRequest.masterVersionKey ~~> self.masterVersion,
            DownloadFileRequest.fileVersionKey ~~> self.fileVersion,
            DownloadFileRequest.cloudFolderNameKey ~~> self.cloudFolderName
        ])
    }
}

class DownloadFileResponse : ResponseMessage {
    public var responseType: ResponseType {
        return .data(data: data)
    }
    
    static let appMetaDataKey = "appMetaData"
    var appMetaData:String?
    
    var data:Data?
    
    static let fileSizeBytesKey = "fileSizeBytes"
    var fileSizeBytes:Int64?
    
    // If the master version for the user on the server has been incremented, this key will be present in the response-- with the new value of the master version. The download was not attempted in this case.
    static let masterVersionUpdateKey = "masterVersionUpdate"
    var masterVersionUpdate:Int64?
    
    required init?(json: JSON) {
        self.masterVersionUpdate = DownloadFileResponse.masterVersionUpdateKey <~~ json
        self.appMetaData = DownloadFileResponse.appMetaDataKey <~~ json
        self.fileSizeBytes = DownloadFileResponse.fileSizeBytesKey <~~ json
    }
    
    convenience init?() {
        self.init(json:[:])
    }
    
    // MARK: - Serialization
    func toJSON() -> JSON? {
        return jsonify([
            DownloadFileResponse.masterVersionUpdateKey ~~> self.masterVersionUpdate,
            DownloadFileResponse.appMetaDataKey ~~> self.appMetaData,
            DownloadFileResponse.fileSizeBytesKey ~~> self.fileSizeBytes
        ])
    }
}
