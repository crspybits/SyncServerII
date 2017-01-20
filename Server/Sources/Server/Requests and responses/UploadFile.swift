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
    var data = Data()
    var sizeOfDataInBytes:Int!
    
    // Files in the cloud are referred to by UUID's. This must be a valid UUID.
    static let cloudFileUUIDKey = "cloudFileUUID"
    var cloudFileUUID:String!
    
    static let mimeTypeKey = "mimeType"
    var mimeType:String!
    
    // A root-level folder in the cloud file service.
    static let cloudFolderNameKey = "cloudFolderName"
    var cloudFolderName:String!
    
    func keys() -> [String] {
        return [UploadFileRequest.cloudFileUUIDKey, UploadFileRequest.mimeTypeKey, UploadFileRequest.cloudFolderNameKey]
    }
    
    required init?(json: JSON) {
        super.init()
        
        self.cloudFileUUID = UploadFileRequest.cloudFileUUIDKey <~~ json
        self.mimeType = UploadFileRequest.mimeTypeKey <~~ json
        self.cloudFolderName = UploadFileRequest.cloudFolderNameKey <~~ json

        if !self.propertiesHaveValues(propertyNames: self.keys()) {
            return nil
        }
        
        guard let _ = NSUUID(uuidString: self.cloudFileUUID) else {
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
}

class UploadFileResponse : ResponseMessage {
    static let resultKey = "result"
    var result: PerfectLib.JSONConvertible?
    static let sizeKey = "sizeInBytes"
    var size:Int64?
    
    // MARK: - Serialization
    func toJSON() -> JSON? {
        return jsonify([
            UploadFileResponse.resultKey ~~> self.result,
            UploadFileResponse.sizeKey ~~> self.size
        ])
    }
}
