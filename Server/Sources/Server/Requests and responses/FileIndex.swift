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
    required init?(json: JSON) {
        super.init()
    }

    func toJSON() -> JSON? {
        return jsonify([
        ])
    }
    
#if SERVER
    required convenience init?(request: RouterRequest) {
        self.init(json: request.queryParameters)
    }
#endif
    
    func allKeys() -> [String] { return [] }
    func nonNilKeys() -> [String] { return [] }
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
    
    func toJSON() -> JSON? {
        return jsonify([
            FileIndexResponse.masterVersionKey ~~> self.masterVersion,
            FileIndexResponse.fileIndexKey ~~> self.fileIndex
        ])
    }
}

