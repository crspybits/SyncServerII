//
//  Repositories.swift
//  Server
//
//  Created by Christopher Prince on 2/7/17.
//
//

import Foundation

struct Repositories {
    let user:UserRepository!
    let lock:LockRepository!
    let masterVersion:MasterVersionRepository!
    let fileIndex:FileIndexRepository!
    let upload:UploadRepository!
    let deviceUUID:DeviceUUIDRepository!
    let sharing:SharingInvitationRepository!
    let sharingGroup: SharingGroupRepository!
    let sharingGroupUser: SharingGroupUserRepository!
}
