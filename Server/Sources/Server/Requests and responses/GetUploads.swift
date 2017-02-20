//
//  GetUploads.swift
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

// Request an index of file uploads (UploadFile) and upload deletions (UploadDeleletion) -- queries the meta data on the sync server. The uploads are specific both to the user and the deviceUUID of the user.

class GetUploadsRequest : NSObject, RequestMessage {
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

class GetUploadsResponse : ResponseMessage {
    public var responseType: ResponseType {
        return .json
    }
    
    static let uploadsKey = "uploads"
    var uploads:[FileInfo]?
    
    required init?(json: JSON) {
        self.uploads = GetUploadsResponse.uploadsKey <~~ json
    }
    
    convenience init?() {
        self.init(json:[:])
    }
    
    // MARK: - Serialization
    func toJSON() -> JSON? {
        return jsonify([
            GetUploadsResponse.uploadsKey ~~> self.uploads
        ])
    }
}
