//
//  CreateSharingInvitation.swift
//  Server
//
//  Created by Christopher Prince on 4/9/17.
//
//

import Foundation
import Gloss

#if SERVER
import Kitura
#endif

class CreateSharingInvitationRequest : NSObject, RequestMessage {
    static let sharingPermissionKey = "sharingPermission"
    var sharingPermission:SharingPermission!

    // You can give either SharingPermission valued keys or string valued keys.
    required init?(json: JSON) {
        super.init()
        
        self.sharingPermission = Decoder.decodeSharingPermission(key: CreateSharingInvitationRequest.sharingPermissionKey, json: json)
        
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
    
    func nonNilKeys() -> [String] {
        return [CreateSharingInvitationRequest.sharingPermissionKey]
    }
    
    func allKeys() -> [String] {
        return self.nonNilKeys()
    }
    
    func toJSON() -> JSON? {
        return jsonify([
            Encoder.encodeSharingPermission(key: CreateSharingInvitationRequest.sharingPermissionKey, value: self.sharingPermission)
        ])
    }
}

extension Encoder {
    static func encodeSharingPermission(key: String, value: SharingPermission?) -> JSON? {
            
        if let value = value {
            return [key : value.rawValue]
        }

        return nil
    }
}

extension Decoder {
    // The sharing permission in the json can be a string or SharingPermission.
    static func decodeSharingPermission(key: String, json: JSON) -> SharingPermission? {
            
        if let sharingPermissionString = json.valueForKeyPath(keyPath: key) as? String {
            return SharingPermission(rawValue: sharingPermissionString)
        }
        
        if let sharingPermission = json[key] as? SharingPermission? {
            return sharingPermission
        }
        
        return nil
    }
}

class CreateSharingInvitationResponse : ResponseMessage {
    static let sharingInvitationUUIDKey = "sharingInvitationUUID"
    var sharingInvitationUUID:String!
    
    public var responseType: ResponseType {
        return .json
    }
    
    required init?(json: JSON) {
        self.sharingInvitationUUID = CreateSharingInvitationResponse.sharingInvitationUUIDKey <~~ json
    }
    
    convenience init?() {
        self.init(json:[:])
    }
    
    // MARK: - Serialization
    func toJSON() -> JSON? {
        return jsonify([
            CreateSharingInvitationResponse.sharingInvitationUUIDKey ~~> self.sharingInvitationUUID
        ])
    }
}
