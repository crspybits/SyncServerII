//
//  FileIndex.swift
//  Server
//
//  Created by Christopher Prince on 1/28/17.
//
//

import Foundation
import Gloss

#if SERVER
import Kitura
#endif

// Request an index of all files that have been uploaded with UploadFile and committed using DoneUploads by the user-- queries the meta data on the sync server.

class FileIndexRequest : NSObject, RequestMessage {
    // MARK: Properties for use in request message.
    
    func nonNilKeys() -> [String] {
        return []
    }
    
    func allKeys() -> [String] {
        return self.nonNilKeys()
    }
    
    required init?(json: JSON) {
        super.init()
        
#if SERVER
        if !self.propertiesHaveValues(propertyNames: self.nonNilKeys()) {
            return nil
        }
#endif
    }
    
#if SERVER
    required convenience init?(request: RouterRequest) {
        self.init(json: request.queryParameters)
    }
#endif

    func toJSON() -> JSON? {
        return jsonify([
        ])
    }
}

class FileIndexResponse : ResponseMessage {
    public var responseType: ResponseType {
        return .json
    }
    
    static let masterVersionKey = "masterVersion"
    var masterVersion:MasterVersionInt!
    
    static let fileIndexKey = "fileIndex"
    var fileIndex:[FileInfo]?
    
    required init?(json: JSON) {
        self.masterVersion = Decoder.decode(int64ForKey: FileIndexResponse.masterVersionKey)(json)        
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
