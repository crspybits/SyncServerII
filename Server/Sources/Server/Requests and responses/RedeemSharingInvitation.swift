//
//  RedeemSharingInvitation.swift
//  Server
//
//  Created by Christopher Prince on 4/12/17.
//
//

import Foundation
import Gloss

#if SERVER
import Kitura
#endif

class RedeemSharingInvitationRequest : NSObject, RequestMessage {
    static let sharingInvitationUUIDKey = "sharingInvitationUUID"
    var sharingInvitationUUID:String!

    required init?(json: JSON) {
        super.init()
        
        self.sharingInvitationUUID = RedeemSharingInvitationRequest.sharingInvitationUUIDKey <~~ json

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
        return [RedeemSharingInvitationRequest.sharingInvitationUUIDKey]
    }
    
    func allKeys() -> [String] {
        return self.nonNilKeys()
    }
    
    func toJSON() -> JSON? {
        return jsonify([
            RedeemSharingInvitationRequest.sharingInvitationUUIDKey ~~> self.sharingInvitationUUID
        ])
    }
}

class RedeemSharingInvitationResponse : ResponseMessage {
    public var responseType: ResponseType {
        return .json
    }
    
    required init?(json: JSON) {
    }
    
    convenience init?() {
        self.init(json:[:])
    }
    
    // MARK: - Serialization
    func toJSON() -> JSON? {
        return jsonify([
        ])
    }
}
