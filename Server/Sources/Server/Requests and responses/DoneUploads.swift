//
//  DoneUploads.swift
//  Server
//
//  Created by Christopher Prince on 1/21/17.
//
//

import Foundation
import Gloss

#if SERVER
import Kitura
import PerfectLib
#endif

class DoneUploadsRequest : NSObject, RequestMessage {
    // MARK: Properties for use in request message.
    
    // Overall version for files for the specific user; assigned by the server.
    static let masterVersionKey = "masterVersion"
    var masterVersion:MasterVersionInt!
    
#if DEBUG
    // Give a time value in seconds -- after the lock is obtained, the server for sleep for this lock to test locking operation.
    static let testLockSyncKey = "testLockSync"
    var testLockSync:Int32?
#endif
    
    func nonNilKeys() -> [String] {
        return [DoneUploadsRequest.masterVersionKey]
    }
    
    func allKeys() -> [String] {
#if DEBUG
        return self.nonNilKeys() + [DoneUploadsRequest.testLockSyncKey]
#else
        return self.nonNilKeys()
#endif
    }
    
    required init?(json: JSON) {
        super.init()
        
        self.masterVersion = DoneUploadsRequest.masterVersionKey <~~ json
#if DEBUG
        self.testLockSync = DoneUploadsRequest.testLockSyncKey <~~ json
#endif

        if !self.propertiesHaveValues(propertyNames: self.nonNilKeys()) {
#if SERVER
            Log.debug(message: "json was: \(json)")
#endif
            return nil
        }
    }
    
#if SERVER
    required convenience init?(request: RouterRequest) {
        self.init(json: request.queryParameters)
    }
#endif
    
    func toJSON() -> JSON? {
        var result = [
            DoneUploadsRequest.masterVersionKey ~~> self.masterVersion
        ]
        
#if DEBUG
        result += [DoneUploadsRequest.testLockSyncKey ~~> self.testLockSync]
#endif
        
        return jsonify(result)
    }
}

class DoneUploadsResponse : ResponseMessage {
    public var responseType: ResponseType {
        return .json
    }
    
    // There are two possible non-error responses to DoneUploads:
    
    // 1) On successful operation, this gives the number of uploads entries transferred to the FileIndex.
    static let numberUploadsTransferredKey = "numberUploadsTransferred"
    var numberUploadsTransferred:Int32?
    
    // 2) If the master version for the user on the server has been incremented, this key will be present in the response-- with the new value of the master version. The doneUploads operation was not attempted in this case.
    static let masterVersionUpdateKey = "masterVersionUpdate"
    var masterVersionUpdate:MasterVersionInt?
    
    required init?(json: JSON) {
        self.numberUploadsTransferred = DoneUploadsResponse.numberUploadsTransferredKey <~~ json
        self.masterVersionUpdate = DoneUploadsResponse.masterVersionUpdateKey <~~ json
    }
    
    convenience init?() {
        self.init(json:[:])
    }
    
    // MARK: - Serialization
    func toJSON() -> JSON? {
        return jsonify([
            DoneUploadsResponse.masterVersionUpdateKey ~~> self.masterVersionUpdate,
            DoneUploadsResponse.numberUploadsTransferredKey ~~> self.numberUploadsTransferred
        ])
    }
}
