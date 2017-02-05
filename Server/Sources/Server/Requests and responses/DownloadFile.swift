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
    
    // Overall version for files for the specific user; assigned by the server.
    static let masterVersionKey = "masterVersion"
    var masterVersion:MasterVersionInt!
    
    func nonNilKeys() -> [String] {
        return [DownloadFileRequest.fileUUIDKey, DownloadFileRequest.deviceUUIDKey, DownloadFileRequest.masterVersionKey]
    }
    
    func allKeys() -> [String] {
        return self.nonNilKeys()
    }
    
    required init?(json: JSON) {
        super.init()
        
        self.fileUUID = DownloadFileRequest.fileUUIDKey <~~ json
        self.deviceUUID = DownloadFileRequest.deviceUUIDKey <~~ json
        self.masterVersion = DownloadFileRequest.masterVersionKey <~~ json

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
            DownloadFileRequest.masterVersionKey ~~> self.masterVersion
        ])
    }
}

class DownloadFileResponse : ResponseMessage {
    static let appMetaDataKey = "appMetaData"
    var appMetaData:String!
    
    static let fileVersionKey = "fileVersion"
    var fileVersion:FileVersionInt!
    
    // If the master version for the user on the server has been incremented, this key will be present in the response-- with the new value of the master version. The download was not attempted in this case.
    static let masterVersionUpdateKey = "masterVersionUpdate"
    var masterVersionUpdate:Int64?
    
    var data = Data()
    var sizeOfDataInBytes:Int!
    
    required init?(json: JSON) {
        self.masterVersionUpdate = DownloadFileResponse.masterVersionUpdateKey <~~ json
        self.fileVersion = DownloadFileResponse.fileVersionKey <~~ json
        self.appMetaData = DownloadFileResponse.appMetaDataKey <~~ json
    }
    
    convenience init?() {
        self.init(json:[:])
    }
    
    // MARK: - Serialization
    func toJSON() -> JSON? {
        return jsonify([
            DownloadFileResponse.masterVersionUpdateKey ~~> self.masterVersionUpdate,
            DownloadFileResponse.appMetaDataKey ~~> self.appMetaData,
            DownloadFileResponse.fileVersionKey ~~> self.fileVersion,
        ])
    }
}
