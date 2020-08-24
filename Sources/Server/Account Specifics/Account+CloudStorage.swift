//
//  Account+CloudStorage.swift
//  Server
//
//  Created by Christopher G Prince on 8/15/20.
//

import Foundation
import ServerAccount
import LoggerAPI

extension Account {
    // Pass as the `mock` the MockStorage if you are using it.
    func cloudStorage(mock: CloudStorage?) -> CloudStorage? {
        var useMockStorage: Bool = false
#if DEBUG
#if DEBUG && MOCK_STORAGE
        useMockStorage = true
#endif
        if let loadTesting = Configuration.server.loadTestingCloudStorage, loadTesting {
            useMockStorage = true
        }
#endif
        Log.debug("cloudStorage: useMockStorage: \(useMockStorage)")
        
        if useMockStorage {
            return mock
        }
        else {
            return self as? CloudStorage
        }
    }
}

