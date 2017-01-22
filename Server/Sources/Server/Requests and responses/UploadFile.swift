//
//  UploadFile.swift
//  Server
//
//  Created by Christopher Prince on 1/15/17.
//
//

import Foundation
import PerfectLib
import Gloss
import Kitura

class UploadFileRequest : NSObject, RequestMessage {
    // MARK: Properties for use in request message.
    
    static let fileUUIDKey = "fileUUID"
    var fileUUID:String!
    
    static let mimeTypeKey = "mimeType"
    var mimeType:String!
    
    // A root-level folder in the cloud file service.
    static let cloudFolderNameKey = "cloudFolderName"
    var cloudFolderName:String!
    
    static let deviceUUIDKey = "deviceUUID"
    var deviceUUID:String!
    
    static let appMetaDataKey = "appMetaData"
    var appMetaData:String!
    
    static let fileVersionKey = "fileVersion"
    // Using a String here because (a) value(forKey: name) doesn't appear to play well with Int's, and (b) because that's how it will arrive in JSON.
    var fileVersion:String!
    
    // Overall version for files for the specific user; assigned by the server.
    static let masterVersionKey = "masterVersion"
    var masterVersion:String!
    
    // MARK: Properties NOT used in the request message.
    
    var data = Data()
    var sizeOfDataInBytes:Int!
    
    var fileVersionNumber:Int32 {
        return Int32(fileVersion)!
    }
    
    var masterVersionNumber:Int {
        return Int(masterVersion)!
    }
    
    func nonNilKeys() -> [String] {
        return [UploadFileRequest.fileUUIDKey, UploadFileRequest.mimeTypeKey, UploadFileRequest.cloudFolderNameKey, UploadFileRequest.deviceUUIDKey, UploadFileRequest.fileVersionKey, UploadFileRequest.masterVersionKey]
    }
    
    func allKeys() -> [String] {
        return self.nonNilKeys() + [UploadFileRequest.appMetaDataKey]
    }
    
    required init?(json: JSON) {
        super.init()
        
        self.fileUUID = UploadFileRequest.fileUUIDKey <~~ json
        self.mimeType = UploadFileRequest.mimeTypeKey <~~ json
        self.cloudFolderName = UploadFileRequest.cloudFolderNameKey <~~ json
        self.deviceUUID = UploadFileRequest.deviceUUIDKey <~~ json
        self.fileVersion = UploadFileRequest.fileVersionKey <~~ json
        self.masterVersion = UploadFileRequest.masterVersionKey <~~ json
        self.appMetaData = UploadFileRequest.appMetaDataKey <~~ json
        
        if !self.propertiesHaveValues(propertyNames: self.nonNilKeys()) {
            return nil
        }
        
        guard let _ = NSUUID(uuidString: self.fileUUID),
            let _ = NSUUID(uuidString: self.deviceUUID) else {
            return nil
        }
    }
    
    required convenience init?(request: RouterRequest) {
        self.init(json: request.queryParameters)
        do {
            // TODO: Eventually this needs to be converted into stream processing where a stream from client is passed along to Google Drive or some other cloud service-- so not all of the file has to be read onto the server. For big files this will crash the server.
            self.sizeOfDataInBytes = try request.read(into: &self.data)
        } catch (let error) {
            Log.error(message: "Could not upload file: \(error)")
            return nil
        }
    }
    
    func toJSON() -> JSON? {
        return jsonify([
            UploadFileRequest.fileUUIDKey ~~> self.fileUUID,
            UploadFileRequest.mimeTypeKey ~~> self.mimeType,
            UploadFileRequest.cloudFolderNameKey ~~> self.cloudFolderName,
            UploadFileRequest.deviceUUIDKey ~~> self.deviceUUID,
            UploadFileRequest.fileVersionKey ~~> self.fileVersion,
            UploadFileRequest.masterVersionKey ~~> self.masterVersion,
            UploadFileRequest.appMetaDataKey ~~> self.appMetaData
        ])
    }
}

class UploadFileResponse : ResponseMessage {
    static let resultKey = "result"
    var result: PerfectLib.JSONConvertible?
    
    // On a successful upload, this will be present in the response.
    static let sizeKey = "sizeInBytes"
    var size:Int64?
    
    // If the master version for the user on the server has been incremented, this key will be present in the response-- with the new value of the master version. The upload was not attempted in this case.
    static let masterVersionUpdateKey = "masterVersionUpdate"
    var masterVersionUpdate:Int64?
    
    required init?(json: JSON) {
        self.size = UploadFileResponse.sizeKey <~~ json
        self.masterVersionUpdate = UploadFileResponse.masterVersionUpdateKey <~~ json
    }
    
    convenience init?() {
        self.init(json:[:])
    }
    
    // MARK: - Serialization
    func toJSON() -> JSON? {
        return jsonify([
            UploadFileResponse.resultKey ~~> self.result,
            UploadFileResponse.sizeKey ~~> self.size,
            UploadFileResponse.masterVersionUpdateKey ~~> self.masterVersionUpdate
        ])
    }
}
