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
import PerfectLib
#endif

// Request an index of all files that have been uploaded with UploadFile and committed using DoneUploads by the user-- queries the meta data on the sync server.

class FileIndexRequest : NSObject, RequestMessage {
#if DEBUG
    // Give a time value in seconds -- the server for sleep to test failure of API calls.
    static let testServerSleepKey = "testServerSleep"
    var testServerSleep:Int32?
#endif
 
    required init?(json: JSON) {
        super.init()
#if DEBUG
        self.testServerSleep = Decoder.decode(int32ForKey: FileIndexRequest.testServerSleepKey)(json)
#endif

#if SERVER
        Log.info(message: "FileIndexRequest.testServerSleep: \(String(describing: testServerSleep))")
#endif

        if !self.propertiesHaveValues(propertyNames: self.nonNilKeys()) {
#if SERVER
            Log.debug(message: "json was: \(json)")
#endif
            return nil
        }
    }

    func toJSON() -> JSON? {
        var result = [JSON?]()
        
#if DEBUG
        result += [FileIndexRequest.testServerSleepKey ~~> self.testServerSleep]
#endif
        
        return jsonify(result)
    }
    
#if SERVER
    required convenience init?(request: RouterRequest) {
        self.init(json: request.queryParameters)
    }
#endif
    
    func allKeys() -> [String] {
#if DEBUG
        return self.nonNilKeys() + [FileIndexRequest.testServerSleepKey]
#else
        return self.nonNilKeys()
#endif
    }
    
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

