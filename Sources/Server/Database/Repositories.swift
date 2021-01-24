//
//  Repositories.swift
//  Server
//
//  Created by Christopher Prince on 2/7/17.
//
//

import Foundation

class Repositories {
    let db: Database
    
    lazy var user = UserRepository(db)
    lazy var fileIndex = FileIndexRepository(db)
    lazy var upload = UploadRepository(db)
    lazy var deviceUUID = DeviceUUIDRepository(db)
    lazy var sharing = SharingInvitationRepository(db)
    lazy var sharingGroup = SharingGroupRepository(db)
    lazy var sharingGroupUser = SharingGroupUserRepository(db)
    lazy var deferredUpload = DeferredUploadRepository(db)

    init(db: Database) {
        self.db = db
    }
}
