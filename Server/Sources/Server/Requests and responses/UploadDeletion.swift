//
//  DeleteFile.swift
//  Server
//
//  Created by Christopher Prince on 2/18/17.
//
//

import Foundation
import Gloss

#if SERVER
import Kitura
#endif

// This places a deletion request in the Upload table on the server. A DoneUploads request is subsequently required to actually perform the deletion in cloud storage.

class UploadDeletionRequest : NSObject, RequestMessage {
    // MARK: Properties for use in request message.
    
    static let fileUUIDKey = "fileUUID"
    var fileUUID:String!
    
    // This must indicate the current version of the file in the FileIndex.
    static let fileVersionKey = "fileVersion"
    var fileVersion:FileVersionInt!
    
    // Overall version for files for the specific user; assigned by the server.
    static let masterVersionKey = "masterVersion"
    var masterVersion:MasterVersionInt!
    
    func nonNilKeys() -> [String] {
        return [UploadDeletionRequest.fileUUIDKey, UploadDeletionRequest.fileVersionKey, UploadDeletionRequest.masterVersionKey]
    }
    
    func allKeys() -> [String] {
        return self.nonNilKeys()
    }
    
    required init?(json: JSON) {
        super.init()
        
        self.fileUUID = UploadDeletionRequest.fileUUIDKey <~~ json
        self.masterVersion = UploadDeletionRequest.masterVersionKey <~~ json
        self.fileVersion = UploadDeletionRequest.fileVersionKey <~~ json
        
        if !self.propertiesHaveValues(propertyNames: self.nonNilKeys()) {
            return nil
        }
        
        guard let _ = NSUUID(uuidString: self.fileUUID) else {
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
            UploadDeletionRequest.fileUUIDKey ~~> self.fileUUID,
            UploadDeletionRequest.masterVersionKey ~~> self.masterVersion,
            UploadDeletionRequest.fileVersionKey ~~> self.fileVersion
        ])
    }
}

class UploadDeletionResponse : ResponseMessage {
    public var responseType: ResponseType {
        return .json
    }
    
    // If the master version for the user on the server has been incremented, this key will be present in the response-- with the new value of the master version. The upload deletion was not attempted in this case.
    static let masterVersionUpdateKey = "masterVersionUpdate"
    var masterVersionUpdate:Int64?
    
    required init?(json: JSON) {
        self.masterVersionUpdate = UploadDeletionResponse.masterVersionUpdateKey <~~ json
    }
    
    convenience init?() {
        self.init(json:[:])
    }
    
    // MARK: - Serialization
    func toJSON() -> JSON? {
        return jsonify([
            UploadDeletionResponse.masterVersionUpdateKey ~~> self.masterVersionUpdate
        ])
    }
}
