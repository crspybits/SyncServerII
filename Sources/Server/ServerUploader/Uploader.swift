import Foundation
import LoggerAPI
import ChangeResolvers
import ServerAccount
import ServerShared

// Processes all entries in DeferredUpload as a unit.
    
class Uploader {
    enum Errors: Error {
        case failedInit
        case failedConnectingDatabase
        case failedToGetDeferredUploads
        case noFileGroupUUID
        case hasFileGroupUUID
        case failedApplyDeferredUploads
    }
    
    private let db: Database
    private let resolverManager: ChangeResolverManager
    private let accountManager: AccountManager
    private let lockName = "Uploader"
    private var applier: ApplyDeferredUploads?
    private let deferredUploadRepo:DeferredUploadRepository
    
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
    
    // Check if there is uploading to do. Uses a lock so it is safe *across* instances of the server. i.e., there will be at most one instance of this running across server instances. Runs asynchronously if it can get the lock.
    // This has no completion handler because we want this to run asynchronously of requests.
    func run(sharingGroupUUID: String) throws {
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
        
        // Sometimes multiple rows in DeferredUpload may refer to the same fileGroupUUID-- so need to process those together. (Except for those with a nil fileGroupUUID-- which are processed independently).
        DispatchQueue.global(qos: .default).async {
            self.process(sharingGroupUUID: sharingGroupUUID, deferredUploads: deferredUploads) { error in
                try? self.release()
                
                if let error = error {
                    // TODO: How to record this failure?
                    Log.error("Failed: \(error)")
                }
                else {
                    Log.info("Succeeded!")
                }
            }
        }
    }
    
    func process(sharingGroupUUID: String, deferredUploads: [DeferredUpload], completion: @escaping (Error?)->()) {
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
        
        let aggregatedGroups = Self.aggregateDeferredUploads(withFileGroupUUIDs: withFileGroupUUIDs)
        
        guard aggregatedGroups.count > 0 else {
            completion(nil)
            return
        }
        
        applyDeferredUploads(sharingGroupUUID: sharingGroupUUID, aggregatedGroups: aggregatedGroups) { error in
            guard error == nil else {
                completion(error)
                return
            }
            
            completion(nil)
            
            // TODO: Apply to files without fileGroupUUID's.
//            for noFileGroupUUID in noFileGroupUUIDs {
//                // try Self.applyWithNoFileGroupUUID(deferredUpload: noFileGroupUUID)
//            }
        }
    }
    
    // Process a deferred upload with no fileGroupUUID
//    static func applyWithNoFileGroupUUID(deferredUpload: DeferredUpload) throws {
//        guard deferredUpload.fileGroupUUID == nil else {
//            throw Errors.hasFileGroupUUID
//        }
//    }
    
    // Process a group of deferred uploads, all with the same fileGroupUUID
    // All DeferredUploads given must be in the fileGroupUUID given.
    func applyDeferredUploads(currentDeferredUpload: Int = 0, sharingGroupUUID: String, aggregatedGroups: [[DeferredUpload]], completion: @escaping (Error?)->()) {

        guard currentDeferredUpload < aggregatedGroups.count else {
            completion(nil)
            return
        }
        
        let aggregatedGroup = aggregatedGroups[currentDeferredUpload]

        guard let fileGroupUUID = aggregatedGroup[0].fileGroupUUID else {
            completion(Errors.noFileGroupUUID)
            return
        }

        guard let applier = try? ApplyDeferredUploads(sharingGroupUUID: sharingGroupUUID, fileGroupUUID: fileGroupUUID, deferredUploads: aggregatedGroup, accountManager: accountManager, resolverManager: resolverManager, db: db) else {
            completion(Errors.failedApplyDeferredUploads)
            return
        }
        
        // `run` executes asynchronously. Need to retain the applier.
        self.applier = applier
        
        applier.run {[unowned self] error in
            guard error == nil else {
                completion(error)
                return
            }
            
            DispatchQueue.global(qos: .default).async {
                self.applyDeferredUploads(currentDeferredUpload: currentDeferredUpload + 1, sharingGroupUUID: sharingGroupUUID, aggregatedGroups: aggregatedGroups, completion: completion)
            }
        }
    }

    // Each DeferredUpload *must* have a non-nil fileGroupUUID. The ordering of the groups in the result is not well defined.
    static func aggregateDeferredUploads(withFileGroupUUIDs: [DeferredUpload]) ->  [[DeferredUpload]] {
    
        guard withFileGroupUUIDs.count > 0 else {
            return [[]]
        }
        
        // Each sub-array has the same fileGroupUUID
        var fileGroupUUIDGroups = [[DeferredUpload]]()

        let sorted = withFileGroupUUIDs.sorted { du1, du2  in
            let fileGroupUUID1 = du1.fileGroupUUID!
            let fileGroupUUID2 = du2.fileGroupUUID!
            return fileGroupUUID1 < fileGroupUUID2
        }
        
        var current = [DeferredUpload]()
        var currentFileGroupUUID: String?
        for deferredUpload in sorted {
            if let fileGroupUUID = currentFileGroupUUID {
                if fileGroupUUID == deferredUpload.fileGroupUUID {
                    current += [deferredUpload]
                }
                else {
                    currentFileGroupUUID = deferredUpload.fileGroupUUID
                    fileGroupUUIDGroups += [current]
                    current = [deferredUpload]
                }
            }
            else {
                currentFileGroupUUID = deferredUpload.fileGroupUUID
                current += [deferredUpload]
            }
        }
        
        fileGroupUUIDGroups += [current]
        return fileGroupUUIDGroups
    }
}
