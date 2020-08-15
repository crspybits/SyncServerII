//
//  SharingGroupsController.swift
//  Server
//
//  Created by Christopher G Prince on 7/15/18.
//

import LoggerAPI
import Credentials
import ServerShared
import Foundation
import ServerAccount

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
        
        guard let accountScheme = params.accountProperties?.accountScheme else {
            let message = "Could not get account scheme from properties!"
            Log.error(message)
            params.completion(.failure(.message(message)))
            return
        }
        
        // My logic here is that a sharing user should only be able to create files in the same sharing group(s) to which they were originally invited. The only way they'll get access to another sharing group is through invitation, not by creating new sharing groups.
        guard accountScheme.userType == .owning else {
            let message = "Current signed in user is not an owning user."
            Log.error(message)
            params.completion(.failure(.message(message)))
            return
        }
        
        guard SharingGroupsController.addSharingGroup(sharingGroupUUID: request.sharingGroupUUID, sharingGroupName: request.sharingGroupName, params: params) else {
            let message = "Failed on adding new sharing group."
            Log.error(message)
            params.completion(.failure(.message(message)))
            return
        }

        guard case .success = params.repos.sharingGroupUser.add(sharingGroupUUID: request.sharingGroupUUID, userId: params.currentSignedInUser!.userId, permission: .admin, owningUserId: nil) else {
            let message = "Failed on adding sharing group user."
            Log.error(message)
            params.completion(.failure(.message(message)))
            return
        }
        
        let response = CreateSharingGroupResponse()
        params.completion(.success(response))
    }
    
    func updateSharingGroup(params:RequestProcessingParameters) {
        guard let request = params.request as? UpdateSharingGroupRequest else {
            let message = "Did not receive UpdateSharingGroupRequest"
            Log.error(message)
            params.completion(.failure(.message(message)))
            return
        }
        
        guard let sharingGroupUUID = request.sharingGroupUUID,
            let sharingGroupName = request.sharingGroupName else {
            Log.info("No name given in sharing group update request-- no change made.")
            let response = UpdateSharingGroupResponse()
            params.completion(.success(response))
            return
        }
        
        guard sharingGroupSecurityCheck(sharingGroupUUID: sharingGroupUUID, params: params) else {
            let message = "Failed in sharing group security check."
            Log.error(message)
            params.completion(.failure(.message(message)))
            return
        }

        let serverSharingGroup = Server.SharingGroup()
        serverSharingGroup.sharingGroupUUID = sharingGroupUUID
        serverSharingGroup.sharingGroupName = sharingGroupName

        guard params.repos.sharingGroup.update(sharingGroup: serverSharingGroup) else {
            let message = "Failed in updating sharing group."
            Log.error(message)
            params.completion(.failure(.message(message)))
            return
        }
        
        let response = UpdateSharingGroupResponse()
        params.completion(.success(response))
    }
    
    func removeSharingGroup(params:RequestProcessingParameters) {
        guard let request = params.request as? RemoveSharingGroupRequest else {
            let message = "Did not receive RemoveSharingGroupRequest"
            Log.error(message)
            params.completion(.failure(.message(message)))
            return
        }
        
        guard sharingGroupSecurityCheck(sharingGroupUUID: request.sharingGroupUUID, params: params) else {
            let message = "Failed in sharing group security check."
            Log.error(message)
            params.completion(.failure(.message(message)))
            return
        }
        
        guard remove(params:params, sharingGroupUUID: request.sharingGroupUUID) else {
            return
        }
        
        let response = RemoveSharingGroupResponse()
        params.completion(.success(response))
    }
    
    private func remove(params:RequestProcessingParameters, sharingGroupUUID: String) -> Bool {
        let markKey = FileIndexRepository.LookupKey.sharingGroupUUID(sharingGroupUUID: sharingGroupUUID)
        guard let _ = params.repos.fileIndex.markFilesAsDeleted(key: markKey) else {
            let message = "Could not mark files as deleted for sharing group!"
            Log.error(message)
            params.completion(.failure(.message(message)))
            return false
        }
        
        // Any users who were members of the sharing group should no longer be members.
        let sharingGroupUserKey = SharingGroupUserRepository.LookupKey.sharingGroupUUID(sharingGroupUUID)
        let removeResult = params.repos.sharingGroupUser.retry {
            return params.repos.sharingGroupUser.remove(key: sharingGroupUserKey)
        }
        switch removeResult {
        case .removed:
            break
            
        case .deadlock:
            let message = "Could not remove sharing group user references: deadlock"
            Log.error(message)
            params.completion(.failure(.message(message)))
            return false
            
        case .waitTimeout:
            let message = "Could not remove sharing group user references: waitTimeout"
            Log.error(message)
            params.completion(.failure(.message(message)))
            return false
            
        case .error(let error):
            let message = "Could not remove sharing group user references: \(error)"
            Log.error(message)
            params.completion(.failure(.message(message)))
            return false
        }
        
        // Mark the sharing group as deleted.
        guard let _ = params.repos.sharingGroup.markAsDeleted(forCriteria:
            .sharingGroupUUID(sharingGroupUUID)) else {
            let message = "Could not mark sharing group as deleted."
            Log.error(message)
            params.completion(.failure(.message(message)))
            return false
        }
        
        // Not going to remove row from master version. People will still be able to get the file index for this sharing group-- to see that all the files are (marked as) deleted. That requires a master version.
        
        return true
    }
    
    func removeUserFromSharingGroup(params:RequestProcessingParameters) {
        guard let request = params.request as? RemoveUserFromSharingGroupRequest else {
            let message = "Did not receive RemoveUserFromSharingGroupRequest"
            Log.error(message)
            params.completion(.failure(.message(message)))
            return
        }
        
        guard sharingGroupSecurityCheck(sharingGroupUUID: request.sharingGroupUUID, params: params) else {
            let message = "Failed in sharing group security check."
            Log.error(message)
            params.completion(.failure(.message(message)))
            return
        }
        
        // Need to count number of users in sharing group-- if this will be the last user need to "remove" the sharing group because no other people will be able to enter it. ("remove" ==  mark the sharing group as deleted).
        var numberSharingUsers:Int!
        if let result:[ServerShared.SharingGroupUser] = params.repos.sharingGroupUser.sharingGroupUsers(forSharingGroupUUID: request.sharingGroupUUID) {
            numberSharingUsers = result.count
        }
        else {
            params.completion(.failure(nil))
        }
        
        guard let accountScheme = params.accountProperties?.accountScheme else {
            let message = "Could not get account scheme from properties!"
            Log.error(message)
            params.completion(.failure(.message(message)))
            return
        }

        // If we're going to remove the user from the sharing group, and this user is an owning user, we should mark any of their sharing users in that sharing group as removed.
        let resetKey = SharingGroupUserRepository.LookupKey.owningUserAndSharingGroup(owningUserId: params.currentSignedInUser!.userId, uuid: request.sharingGroupUUID)
        if accountScheme.userType == .owning {
            guard params.repos.sharingGroupUser.resetOwningUserIds(key: resetKey) else {
                let message = "Could not reset owning users ids."
                Log.error(message)
                params.completion(.failure(.message(message)))
                return
            }
        }
        
        let removalKey = SharingGroupUserRepository.LookupKey.primaryKeys(sharingGroupUUID: request.sharingGroupUUID, userId: params.currentSignedInUser!.userId)
        let removalResult = params.repos.sharingGroupUser.retry {
            return params.repos.sharingGroupUser.remove(key: removalKey)
        }
        guard case .removed(let numberRows) = removalResult, numberRows == 1 else {
            let message = "Could not remove user from SharingGroup."
            Log.error(message)
            params.completion(.failure(.message(message)))
            return
        }
        
        // Any files that this user has in the FileIndex for this sharing group should be marked as deleted.
        let markKey = FileIndexRepository.LookupKey.userAndSharingGroup(params.currentSignedInUser!.userId, sharingGroupUUID: request.sharingGroupUUID)
        guard let _ = params.repos.fileIndex.markFilesAsDeleted(key: markKey) else {
            let message = "Could not mark files as deleted for user and sharing group!"
            Log.error(message)
            params.completion(.failure(.message(message)))
            return
        }

        if numberSharingUsers == 1 {
            guard remove(params:params, sharingGroupUUID: request.sharingGroupUUID) else {
                return
            }
        }
        
        let response = RemoveUserFromSharingGroupResponse()
        params.completion(.success(response))
    }
}

extension SharingGroupsController {
    // Adds a sharing group, and also adds a sharing group lock.
    // Return true iff success.
    static func addSharingGroup(sharingGroupUUID: String, sharingGroupName: String?, params:RequestProcessingParameters) -> Bool {
        
        guard case .success = params.repos.sharingGroup.add(sharingGroupUUID: sharingGroupUUID, sharingGroupName: sharingGroupName) else {
            let message = "Failed on adding new sharing group."
            Log.error(message)
            return false
        }
        
        return true
    }
}
