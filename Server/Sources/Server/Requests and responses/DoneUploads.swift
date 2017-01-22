//
//  DoneUploads.swift
//  Server
//
//  Created by Christopher Prince on 1/21/17.
//
//

import Foundation
import PerfectLib
import Gloss
import Kitura

class DoneUploadsRequest : NSObject, RequestMessage {
    // MARK: Properties for use in request message.
    
    static let deviceUUIDKey = "deviceUUID"
    var deviceUUID:String!
    
    // Overall version for files for the specific user; assigned by the server.
    static let masterVersionKey = "masterVersion"
    var masterVersion:String!
    
    var masterVersionNumber:Int {
        return Int(masterVersion)!
    }
    
    func nonNilKeys() -> [String] {
        return [DoneUploadsRequest.masterVersionKey, DoneUploadsRequest.deviceUUIDKey]
    }
    
    func allKeys() -> [String] {
        return self.nonNilKeys()
    }
    
    required init?(json: JSON) {
        super.init()
        
        self.masterVersion = DoneUploadsRequest.masterVersionKey <~~ json
        self.deviceUUID = DoneUploadsRequest.deviceUUIDKey <~~ json

        if !self.propertiesHaveValues(propertyNames: self.nonNilKeys()) {
            return nil
        }
    }
    
    required convenience init?(request: RouterRequest) {
        self.init(json: request.queryParameters)
    }
    
    func toJSON() -> JSON? {
        return jsonify([
            DoneUploadsRequest.masterVersionKey ~~> self.masterVersion,
            DoneUploadsRequest.deviceUUIDKey ~~> self.deviceUUID
        ])
    }
}

class DoneUploadsResponse : ResponseMessage {
    static let resultKey = "result"
    var result: PerfectLib.JSONConvertible?
    
    // If the master version for the user on the server has been incremented, this key will be present in the response-- with the new value of the master version. The doneUploads operation was not attempted in this case.
    static let masterVersionUpdateKey = "masterVersionUpdate"
    var masterVersionUpdate:Int64?
    
    required init?(json: JSON) {
    }
    
    convenience init?() {
        self.init(json:[:])
    }
    
    // MARK: - Serialization
    func toJSON() -> JSON? {
        return jsonify([
            DoneUploadsResponse.masterVersionUpdateKey ~~> self.masterVersionUpdate
        ])
    }
}
