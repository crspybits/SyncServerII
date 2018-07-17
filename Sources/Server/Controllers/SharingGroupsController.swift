//
//  SharingGroupsController.swift
//  Server
//
//  Created by Christopher G Prince on 7/15/18.
//

import LoggerAPI
import Credentials
import SyncServerShared
import Foundation

class SharingGroupsController : ControllerProtocol {
    static func setup() -> Bool {
        return true
    }
    
    func getSharingGroups(params:RequestProcessingParameters) {
        guard let _ = params.request as? GetSharingGroupsRequest else {
            let message = "Did not receive GetSharingGroupsRequest"
            Log.error(message)
            params.completion(.failure(.message(message)))
            return
        }
        
        let response = GetSharingGroupsResponse()!

        guard let groups = params.repos.sharingGroupUser.sharingGroups(forUserId: params.currentSignedInUser!.userId) else {
            let message = "Could not get sharing groups for user."
            Log.error(message)
            params.completion(.failure(.message(message)))
            return
        }
        
        let sharingGroupIds = groups.filter{$0.sharingGroupId != nil}.map {$0.sharingGroupId!}
        
        guard sharingGroupIds.count == groups.count else {
            let message = "At least one of the sharing group id's was nil!"
            Log.error(message)
            params.completion(.failure(.message(message)))
            return
        }
        
        response.sharingGroupIds = sharingGroupIds
        
        params.completion(.success(response))
    }
}
