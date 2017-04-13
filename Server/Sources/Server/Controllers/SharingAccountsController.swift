//
//  SharingAccountsController
//  Server
//
//  Created by Christopher Prince on 4/9/17.
//
//

import PerfectLib
import Credentials

class SharingAccountsController : ControllerProtocol {
    class func setup(db:Database) -> Bool {
        if case .failure(_) = SharingInvitationRepository(db).create() {
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
            owningUserId: params.currentSignedInUser!.userId,
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
}
