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
    
    static let fileNameKey = "fileName"
    var fileName:String!
    
    static let mimeTypeKey = "mimeType"
    var mimeType:String!
    
    func keys() -> [String] {
        return [UploadFileRequest.fileNameKey, UploadFileRequest.mimeTypeKey]
    }
    
    required init?(json: JSON) {
        super.init()
        
        self.fileName = UploadFileRequest.fileNameKey <~~ json
        self.mimeType = UploadFileRequest.mimeTypeKey <~~ json
        
        if !self.propertiesHaveValues(propertyNames: self.keys()) {
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
