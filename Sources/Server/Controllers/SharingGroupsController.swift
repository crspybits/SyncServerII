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
    
    func createSharingGroup(params:RequestProcessingParameters) {
        guard let request = params.request as? CreateSharingGroupRequest else {
            let message = "Did not receive CreateSharingGroupRequest"
            Log.error(message)
            params.completion(.failure(.message(message)))
            return
        }
        
        guard case .success(let sharingGroupId) = params.repos.sharingGroup.add(sharingGroupName: request.sharingGroup.sharingGroupName) else {
            let message = "Failed on adding new sharing group."
            Log.error(message)
            params.completion(.failure(.message(message)))
            return
        }

        guard case .success = params.repos.sharingGroupUser.add(sharingGroupId: sharingGroupId, userId: params.currentSignedInUser!.userId) else {
            let message = "Failed on adding sharing group user."
            Log.error(message)
            params.completion(.failure(.message(message)))
            return
        }
        
        if !params.repos.masterVersion.initialize(sharingGroupId: sharingGroupId) {
            let message = "Failed on creating MasterVersion record for sharing group!"
            Log.error(message)
            params.completion(.failure(.message(message)))
            return
        }
        
        let response = CreateSharingGroupResponse()!
        response.sharingGroupId = sharingGroupId
        
        params.completion(.success(response))
    }
    
    func updateSharingGroup(params:RequestProcessingParameters) {
        guard let request = params.request as? UpdateSharingGroupRequest else {
            let message = "Did not receive UpdateSharingGroupRequest"
            Log.error(message)
            params.completion(.failure(.message(message)))
            return
        }
        
        guard let sharingGroupId = request.sharingGroupId,
            let sharingGroupName = request.sharingGroupName else {
            Log.info("No name given in sharing group update request-- no change made.")
            let response = UpdateSharingGroupResponse()!
            params.completion(.success(response))
            return
        }
        
        guard sharingGroupSecurityCheck(sharingGroupId: sharingGroupId, params: params) else {
            let message = "Failed in sharing group security check."
            Log.error(message)
            params.completion(.failure(.message(message)))
            return
        }
        
        let serverSharingGroup = Server.SharingGroup()
        serverSharingGroup.sharingGroupId = sharingGroupId
        serverSharingGroup.sharingGroupName = sharingGroupName

        guard params.repos.sharingGroup.update(sharingGroup: serverSharingGroup) else {
            let message = "Failed in updating sharing group."
            Log.error(message)
            params.completion(.failure(.message(message)))
            return
        }
        
        let response = UpdateSharingGroupResponse()!
        params.completion(.success(response))
    }
    
    func removeSharingGroup(params:RequestProcessingParameters) {
        guard let request = params.request as? RemoveSharingGroupRequest else {
            let message = "Did not receive RemoveSharingGroupRequest"
            Log.error(message)
            params.completion(.failure(.message(message)))
            return
        }
        
        guard sharingGroupSecurityCheck(sharingGroupId: request.sharingGroupId, params: params) else {
            let message = "Failed in sharing group security check."
            Log.error(message)
            params.completion(.failure(.message(message)))
            return
        }
        
        guard let count = params.repos.fileIndex.markFilesAsDeleted(forCriteria: .sharingGroupId("\(request.sharingGroupId!)")), count == 1 else {
            let message = "Could not mark files as deleted for sharing group!"
            Log.error(message)
            params.completion(.failure(.message(message)))
            return
        }
        
        // Any users who were members of the sharing group should no longer be members.
        let sharingGroupUserKey = SharingGroupUserRepository.LookupKey.sharingGroupId(request.sharingGroupId)
        switch params.repos.sharingGroupUser.remove(key: sharingGroupUserKey) {
        case .removed:
            break
        case .error(let error):
            let message = "Could not remove sharing group user references: \(error)"
            Log.error(message)
            params.completion(.failure(.message(message)))
            return
        }
        
        // Mark the sharing group as deleted.
        guard let _ = params.repos.sharingGroup.markAsDeleted(forCriteria:
            .sharingGroupId(request.sharingGroupId)) else {
            let message = "Could not mark sharing group as deleted."
            Log.error(message)
            params.completion(.failure(.message(message)))
            return
        }
        
        // Not going to remove row from master version. People will still be able to get the file index for this sharing group-- to see that all the files are (marked as) deleted. That requires a master version.
        
        let response = RemoveSharingGroupResponse()!
        params.completion(.success(response))
    }
}
