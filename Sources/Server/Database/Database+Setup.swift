//
//  Database+Setup.swift
//  Server
//
//  Created by Christopher G Prince on 6/26/18.
//

import Foundation

extension Database {
    typealias Repo = Repository & RepositoryBasics
    static let repoTypes:[Repo.Type] = [
        SharingGroupRepository.self,
        UserRepository.self,
        DeviceUUIDRepository.self,
        UploadRepository.self,
        FileIndexRepository.self,
        LockRepository.self,
        SharingInvitationRepository.self,
        SharingGroupUserRepository.self,
        MasterVersionRepository.self
    ]
    
    static func setup() -> Bool {
        let db = Database(showStartupInfo: true)

        // The ordering of these table creations is important because of foreign key constraints.

        for repoType in repoTypes {
            let repo = repoType.init(db)
            if case .failure(_) = repo.upcreate() {
                return false
            }
        }
        
        return true
    }
    
#if DEBUG
    static func remove() {
        // Reversing the order on removal to deal with foreign key constraints.
        let reversedRepoTypes = repoTypes.reversed()
        
        let db = Database(showStartupInfo: false)

        for repoType in reversedRepoTypes {
            let repo = repoType.init(db)
            _ = repo.remove()
        }
    }
#endif
}
