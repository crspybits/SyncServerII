import Foundation
import LoggerAPI
import ChangeResolvers
import ServerAccount
import ServerShared

// Processes entries in DeferredUpload in file group-based units.

// For testing.
protocol UploaderProtocol {
    func run() throws
    var delegate: UploaderDelegate? {get set}
}

protocol UploaderDelegate: AnyObject {
    func run(completed: UploaderProtocol, error: Swift.Error?)
}

class Uploader: UploaderProtocol {
    enum Errors: Error {
        case failedInit
        case failedConnectingDatabase
        case failedToGetDeferredUploads
        case missingGroupUUID
        case hasFileGroupUUID
        case failedApplyDeferredUploads
    }
    
    private let db: Database
    private let resolverManager: ChangeResolverManager
    private let accountManager: AccountManager
    private let lockName = "Uploader"
    private let deferredUploadRepo:DeferredUploadRepository
    
    // For testing
    weak var delegate: UploaderDelegate?
    
    init(resolverManager: ChangeResolverManager, accountManager: AccountManager) throws {
        // Need a separate database connection-- to have a separate transaction and to acquire lock.
        guard let db = Database() else {
            throw Errors.failedConnectingDatabase
        }
        
        self.db = db
        self.resolverManager = resolverManager
        self.accountManager = accountManager
        self.deferredUploadRepo = DeferredUploadRepository(db)
    }
    
    private func release() throws {
        try db.releaseLock(lockName: lockName)
    }
    
    // Check if there is uploading to do. e.g., DeferredUpload records. Uses a lock so it is safe *across* instances of the server. i.e., there will be at most one instance of this running across server instances. Runs asynchronously if it can get the lock.
    // This has no completion handler because we want this to run asynchronously of requests.
    func run() throws {
        // Holding a lock here so that, across server instances, at most one Uploader can be running at one time.
        guard try db.getLock(lockName: lockName) else {
            return
        }
        
        guard let deferredUploads = deferredUploadRepo.select(rowsWithStatus: .pending) else {
            try release()
            throw Errors.failedToGetDeferredUploads
        }
        
        guard deferredUploads.count > 0 else {
            // No deferred uploads to process
            try release()
            return
        }
        
        let nonUniqueSharingGroupUUIDs = deferredUploads.compactMap {$0.sharingGroupUUID}
        guard nonUniqueSharingGroupUUIDs.count == deferredUploads.count else {
            try release()
            throw Errors.failedToGetDeferredUploads
        }

        // Processes multiple rows in DeferredUpload when they refer to the same fileGroupUUID together. (Except for those with a nil fileGroupUUID-- which are processed independently).
        DispatchQueue.global().async {
            self.process(deferredUploads: deferredUploads) { error in
                try? self.release()
                
                if let error = error {
                    // TODO: How to record this failure?
                    Log.error("Failed: \(error)")
                }
                else {
                    Log.info("Succeeded!")
                }
                
                Log.debug("Calling run delegate method: \(String(describing: error))")
                self.delegate?.run(completed: self, error: error)
            }
        }
    }
    
    // Assumes all `deferredUploads` have a sharingGroupUUID.
    private func process(deferredUploads: [DeferredUpload], completion: @escaping (Error?)->()) {
    
        var noFileGroupUUIDs = [DeferredUpload]()
        var withFileGroupUUIDs = [DeferredUpload]()
        for deferredUpload in deferredUploads {
            if deferredUpload.fileGroupUUID == nil {
                noFileGroupUUIDs += [deferredUpload]
            }
            else {
                withFileGroupUUIDs += [deferredUpload]
            }
        }
        
        // TODO: Fix
        assert(noFileGroupUUIDs.count == 0)
        
        var aggregatedGroups = [[DeferredUpload]]()

        let aggregateBySharingGroups = Self.aggregateSharingGroupUUIDs(deferredUploads: withFileGroupUUIDs)
        for aggregateForSingleSharingGroup in aggregateBySharingGroups {
            // We have a list of deferred uploads, all with the same sharing group.
            // Next, partition that by file group.
            let aggregatedByFileGroups = Self.aggregateFileGroupUUIDs(deferredUploads: aggregateForSingleSharingGroup)
            
            aggregatedGroups += aggregatedByFileGroups
        }
        
        guard aggregatedGroups.count > 0 else {
            completion(nil)
            return
        }
        
        let result = self.applyDeferredUploads(aggregatedGroups: aggregatedGroups)
        completion(result)
        return
        
        /*
        guard noFileGroupUUIDs.count > 0 else {
            completion(result)
            return
        }
        */

        // When a DeferredUpload has a nil fileGroupUUID-- it necessarily means that there is just a single Upload associated with it.
        
        // let uploadsAggregatedByFileUUID =
        
        // TODO: Apply to files without fileGroupUUID's.
        // Need to partition these by fileUUID-- i.e., to apply all changes for a single file at one time.
        
//            for noFileGroupUUID in noFileGroupUUIDs {
//                // try Self.applyWithNoFileGroupUUID(deferredUpload: noFileGroupUUID)
//            }
    }
    
    // Process a deferred upload with no fileGroupUUID
//    static func applyWithNoFileGroupUUID(deferredUpload: DeferredUpload) throws {
//        guard deferredUpload.fileGroupUUID == nil else {
//            throw Errors.hasFileGroupUUID
//        }
//    }
    
    // Synchronously process each group of deferred uploads, all with the same fileGroupUUID.
    // Each of the aggregated groups must partition the collection of fileGroupUUID's. e.g., two of the sublists cannot contain the same fileGroupUUID, and each sublist must contain deferred uploads with the same fileGroupUUID.
    func applyDeferredUploads(aggregatedGroups: [[DeferredUpload]]) -> Error? {
        var applier: ApplyDeferredUploads!

        func apply(aggregatedGroup: [DeferredUpload], completion: @escaping (Swift.Result<Void, Error>) -> ()) {
            guard aggregatedGroup.count > 0,
                let fileGroupUUID = aggregatedGroup[0].fileGroupUUID,
                let sharingGroupUUID = aggregatedGroup[0].sharingGroupUUID else {
                completion(.failure(Errors.missingGroupUUID))
                return
            }
            
            // `applier.run` executes asynchronously. Need to retain the applier.
            
            applier = try? ApplyDeferredUploads(sharingGroupUUID: sharingGroupUUID, fileGroupUUID: fileGroupUUID, deferredUploads: aggregatedGroup, accountManager: accountManager, resolverManager: resolverManager, db: db)
            
            guard applier != nil else {
                completion(.failure(Errors.failedApplyDeferredUploads))
                return
            }
                        
            applier.run { error in
                if let error = error {
                    completion(.failure(error))
                    return
                }
                completion(.success(()))
            }
        }
        
        let result = aggregatedGroups.synchronouslyRun(apply: apply)
        switch result {
        case .failure(let error):
            return error
        case .success:
            return nil
        }
    }

    // Each DeferredUpload *must* have a non-nil fileGroupUUID. The ordering of the groups in the result is not well defined.
    // Each sub-array in result has the same fileGroupUUID
    static func aggregateFileGroupUUIDs(deferredUploads: [DeferredUpload]) ->  [[DeferredUpload]] {
        return aggregate(deferredUploads: deferredUploads, using: \.fileGroupUUID)
    }

    // Each DeferredUpload *must* have a non-nil sharingGroupUUID. The ordering of the groups in the result is not well defined.
    // Each sub-array in result has the same sharingGroupUUID
    static func aggregateSharingGroupUUIDs(deferredUploads: [DeferredUpload]) ->  [[DeferredUpload]] {
        return aggregate(deferredUploads: deferredUploads, using: \.sharingGroupUUID)
    }
    
    static func aggregate(deferredUploads: [DeferredUpload], using keyPath: KeyPath<DeferredUpload, String?>) ->  [[DeferredUpload]] {
    
        guard deferredUploads.count > 0 else {
            return [[]]
        }
        
        // Each sub-array has the same value for keyPath
        var aggregated = [[DeferredUpload]]()

        let sorted = deferredUploads.sorted { du1, du2  in
            guard let value1 = du1[keyPath: keyPath],
                let value2 = du2[keyPath: keyPath] else {
                return false
            }
            return value1 < value2
        }
        
        var current = [DeferredUpload]()
        var currentKeyValue: String?
        for deferredUpload in sorted {
            if let keyValue = currentKeyValue {
                if keyValue == deferredUpload[keyPath: keyPath] {
                    current += [deferredUpload]
                }
                else {
                    currentKeyValue = deferredUpload[keyPath: keyPath]
                    aggregated += [current]
                    current = [deferredUpload]
                }
            }
            else {
                currentKeyValue = deferredUpload[keyPath: keyPath]
                current += [deferredUpload]
            }
        }
        
        aggregated += [current]
        return aggregated
    }
}
