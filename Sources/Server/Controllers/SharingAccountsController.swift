//
//  SharingAccountsController
//  Server
//
//  Created by Christopher Prince on 4/9/17.
//
//

import PerfectLib
import Credentials
import SyncServerShared

class SharingAccountsController : ControllerProtocol {
    class func setup(db:Database) -> Bool {
        if case .failure(_) = SharingInvitationRepository(db).upcreate() {
            return false
        }
        
        return true
    }
    
    init() {
    }
    
    func createSharingInvitation(params:RequestProcessingParameters) {
        assert(params.ep.authenticationLevel == .secondary)
        assert(params.ep.minSharingPermission == .admin)

        guard let createSharingInvitationRequest = params.request as? CreateSharingInvitationRequest else {
            Log.error(message: "Did not receive CreateSharingInvitationRequest")
            params.completion(nil)
            return
        }

        let result = SharingInvitationRepository(params.db).add(
            owningUserId: params.currentSignedInUser!.effectiveOwningUserId,
            sharingPermission: createSharingInvitationRequest.sharingPermission)
        
        guard case .success(let sharingInvitationUUID) = result else {
            Log.error(message: "Failed to add Sharing Invitation")
            params.completion(nil)
            return
        }
        
        let response = CreateSharingInvitationResponse()!
        response.sharingInvitationUUID = sharingInvitationUUID
        params.completion(response)
    }
    
    func redeemSharingInvitation(params:RequestProcessingParameters) {
        assert(params.ep.authenticationLevel == .primary)
        
        guard let request = params.request as? RedeemSharingInvitationRequest else {
            Log.error(message: "Did not receive RedeemSharingInvitationRequest")
            params.completion(nil)
            return
        }
        
        let userExists = UserController.userExists(userProfile: params.userProfile!, userRepository: params.repos.user)
        switch userExists {
        case .doesNotExist:
            break
        case .error, .exists(_):
            Log.error(message: "Could not add user: Already exists!")
            params.completion(nil)
            return
        }
        
        // Remove stale invitations.
        let removalKey = SharingInvitationRepository.LookupKey.staleExpiryDates
        let removalResult = SharingInvitationRepository(params.db).remove(key: removalKey)
        
        guard case .removed(_) = removalResult else{
            Log.error(message: "Failed removing stale sharing invitations")
            params.completion(nil)
            return
        }
        
        // What I want to do at this point is to simultaneously and atomically, (a) lookup the sharing invitation, and (b) delete it. I believe that since (i) I'm using mySQL transactions, and (ii) InnoDb with a default transaction level of REPEATABLE READ, this should work by first doing the lookup, and then doing the delete.
        
        let sharingInvitationKey = SharingInvitationRepository.LookupKey.sharingInvitationUUID(uuid: request.sharingInvitationUUID)
        let lookupResult = SharingInvitationRepository(params.db).lookup(key: sharingInvitationKey, modelInit: SharingInvitation.init)
        
        guard case .found(let model) = lookupResult,
            let sharingInvitation = model as? SharingInvitation else {
            Log.error(message: "Could not find sharing invitation: \(request.sharingInvitationUUID). Was it stale?")
            params.completion(nil)
            return
        }
        
        let removalResult2 = SharingInvitationRepository(params.db).remove(key: sharingInvitationKey)
        guard case .removed(let numberRemoved) = removalResult2, numberRemoved == 1 else {
            Log.error(message: "Failed removing sharing invitation!")
            params.completion(nil)
            return
        }
        
        // All seems good. Let's create the new sharing user.
        
        // No database creds because this is a new sharing user-- so use params.profileCreds
        
        let user = User()
        user.username = params.userProfile!.displayName
        user.accountType = AccountType.for(userProfile: params.userProfile!)
        user.credsId = params.userProfile!.id
        user.creds = params.profileCreds!.toJSON()
        
        user.userType = .sharing
        user.sharingPermission = sharingInvitation.sharingPermission
        user.owningUserId = sharingInvitation.owningUserId
        
        let userId = params.repos.user.add(user: user)
        if userId == nil {
            Log.error(message: "Failed on adding sharing user to User!")
            params.completion(nil)
            return
        }
        
        let response = RedeemSharingInvitationResponse()!
        params.completion(response)
    }
}
