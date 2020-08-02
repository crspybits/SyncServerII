import Foundation
import LoggerAPI
import ChangeResolvers
import ServerAccount
import ServerShared

// TODO: Need to make sure, when the FileIndex, gets uploaded, that any deletion flag is not changed. In general, only update the fields we're intending to update. This is releant for UploadDeletion which will change the FileIndex in the primary UploadDeletion request processing.

// Processes entries in DeferredUpload in file group-based units and sharing group-based units.

// For testing.
protocol UploaderProtocol {
    func run() throws
    var delegate: UploaderDelegate? {get set}
}

protocol UploaderDelegate: AnyObject {
    func run(completed: UploaderProtocol, error: Swift.Error?)
}

// When the run method finishes: (a) the delegate method is called, if any, and (b) the uploaderRunCompleted notification is posted.
// The userInfo payload of the notification has one key: errorKey, with either nil or a Swift.Error value.
class Uploader: UploaderProtocol {
    // For testing
    static let uploaderRunCompleted = Notification.Name("UploaderRunCompleted")
    static let errorKey = "error"

    enum Errors: Error {
        case failedInit
        case failedConnectingDatabase
        case failedToGetDeferredUploads
        case noGroups
        case missingGroupUUID
        case hasFileGroupUUID
        case failedApplyDeferredUploads
        case failedToGetNonUniqueSharingGroupUUIDs
        case mismatchWithDeferredUploadIdsCount
        case couldNotLookupByGroups
        case failedGettingCloudStorage
        case failedToGetUploads
        case failedToGetSharingGroupUUID
        case failedToGetFileUUID
        case couldNotRemoveUploadRow
        case failedStartingDatabaseTransaction
        case failedCommittingDatabaseTransaction
    }
    
    let db: Database
    private let resolverManager: ChangeResolverManager
    let accountManager: AccountManager
    private let lockName = "Uploader"
    let deferredUploadRepo:DeferredUploadRepository
    let uploadRepo:UploadRepository
    let fileIndexRepo:FileIndexRepository
    let userRepo: UserRepository
    
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
        self.uploadRepo = UploadRepository(db)
        self.fileIndexRepo = FileIndexRepository(db)
        self.userRepo = UserRepository(db)
    }
    
    private func getLock() throws -> Bool {
        return try db.getLock(lockName: lockName)
    }
    
    private func releaseLock() throws {
        try db.releaseLock(lockName: lockName)
    }
    
    // Check if there is uploading to do. e.g., DeferredUpload records. Uses a lock so it is safe *across* instances of the server. i.e., there will be at most one instance of this running across server instances. Runs asynchronously if it can get the lock.
    // This has no completion handler because we want this to run asynchronously of requests.
    func run() throws {
        // Holding a lock here so that, across server instances, at most one Uploader can be running at one time.
        Log.debug("Attempting to get lock...")
        guard try getLock() else {
            Log.debug("Could not get lock.")
            return
        }
        
        Log.debug("Got lock!")

        guard let deferredFileDeletions = deferredUploadRepo.select(rowsWithStatus: [.pendingDeletion]) else {
            Log.error("Failed setting up select to get deferred upload deletions")
            try releaseLock()
            throw Errors.failedToGetDeferredUploads
        }
        
        // Must do pruning based on deletions before fetching the deferred file changes. Because the pruning may remove some of the deferred file changes.
        guard pruneFileUploads(deferredFileDeletions: deferredFileDeletions) else {
            Log.error("Failed pruning file uploads.")
            try releaseLock()
            throw Errors.failedToGetDeferredUploads
        }
        
        guard let deferredFileChangeUploads = deferredUploadRepo.select(rowsWithStatus: [.pendingChange]) else {
            Log.error("Failed fetching deferred file change uploads")
            try releaseLock()
            throw Errors.failedToGetDeferredUploads
        }
        
        guard deferredFileChangeUploads.count > 0 || deferredFileDeletions.count > 0 else {
            Log.debug("No deferred upload changes or deletions to process")
            try releaseLock()
            return
        }
        
        let nonUniqueSharingGroupUUIDs = deferredFileChangeUploads.compactMap {$0.sharingGroupUUID}
        guard nonUniqueSharingGroupUUIDs.count == deferredFileChangeUploads.count else {
            Log.error("Could not get nonUniqueSharingGroupUUIDs")
            try releaseLock()
            throw Errors.failedToGetNonUniqueSharingGroupUUIDs
        }
        
        Log.info("About to start async processing.")
        
        DispatchQueue.global().async {
            do {
                try self.processFileDeletions(deferredUploads: deferredFileDeletions)
            } catch let error {
                self.finishRun(error: error)
                return
            }

            self.processFileChanges(deferredUploads: deferredFileChangeUploads) { error in
                self.finishRun(error: error)
            }
        }
    }
    
    private func finishRun(error: Error?) {
        try? releaseLock()

        if let error = error {
            recordGlobalError(error)
            Log.error("Failed: \(error)")
        }
        else {
            Log.info("Succeeded!")
        }
        
        Log.debug("Calling run delegate method: \(String(describing: error))")
        
        // Don't put `self` into this as the `object`-- get a failing conversion error to NSObject
        let notification = Notification(name: Self.uploaderRunCompleted, object: nil, userInfo: [Self.errorKey: error as Any])
        
        NotificationCenter.default.post(notification)

        delegate?.run(completed: self, error: error)
    }
    
    private func recordGlobalError(_ error: Error) {
    }
    
    // Assumes all `deferredUploads` have a sharingGroupUUID.
    private func processFileChanges(deferredUploads: [DeferredUpload], completion: @escaping (Swift.Error?)->()) {
    
        Log.debug("Starting to process.")
        
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
        
        var aggregateBySharingGroups = [[DeferredUpload]]()
        
        if withFileGroupUUIDs.count > 0 {
            var aggregatedGroups = [[DeferredUpload]]()
            aggregateBySharingGroups = Self.aggregateSharingGroupUUIDs(deferredUploads: withFileGroupUUIDs)
            for aggregateForSingleSharingGroup in aggregateBySharingGroups {
                // We have a list of deferred uploads, all with the same sharing group.
                // Next, partition that by file group.
                let aggregatedByFileGroups = Self.aggregateFileGroupUUIDs(deferredUploads: aggregateForSingleSharingGroup)
                
                aggregatedGroups += aggregatedByFileGroups
            }

            Log.debug("applyDeferredUploads: with file groups")
            if let error = self.applyDeferredUploads(aggregatedGroups: aggregatedGroups, withFileGroupUUID: true) {
                completion(error)
            }
        }
        
        // Next: Deal with any DeferredUpload's that don't have fileGroupUUID's
        
        guard noFileGroupUUIDs.count > 0 else {
            completion(nil)
            return
        }
        
        // Use the basic ApplyDeferredUpload's algorithm-- but without consideration for fileGroupUUID. That basic algorithm gets all the Upload records for all the DeferredUpload's, aggregates by fileUUID, and then applies changes to individual file's.
    
        // We do, however, need to partition these by sharingGroupUUID. ApplyDeferedUploads, used by aggregateSharingGroupUUIDs, relies on each partition having the same sharingGroupUUID.
        
        aggregateBySharingGroups = Self.aggregateSharingGroupUUIDs(deferredUploads: noFileGroupUUIDs)
    
        Log.debug("applyDeferredUploads: without file groups")
        completion(self.applyDeferredUploads(aggregatedGroups: aggregateBySharingGroups, withFileGroupUUID: false))
    }
    
    // When withFileGroupUUID is true: Synchronously process each group of deferred uploads, all with the same fileGroupUUID.
    // Each of the aggregated groups must partition the collection of fileGroupUUID's. e.g., two of the sublists cannot contain the same fileGroupUUID, and each sublist must contain deferred uploads with the same fileGroupUUID.
    // When withFileGroupUUID is false: Similar processing, except without file groups. Each set of changes for the same fileUUID is processed as a unit.
    func applyDeferredUploads(aggregatedGroups: [[DeferredUpload]], withFileGroupUUID: Bool) -> Error? {
        var applier: ApplyDeferredUploads!

        func apply(aggregatedGroup: [DeferredUpload], completion: @escaping (Swift.Result<Void, Error>) -> ()) {
        
            guard aggregatedGroup.count > 0 else {
                completion(.failure(Errors.noGroups))
                return
            }

            var fileGroupUUID: String?
            if withFileGroupUUID {
                guard let fgUUID = aggregatedGroup[0].fileGroupUUID else {
                    completion(.failure(Errors.missingGroupUUID))
                    return
                }
                
                fileGroupUUID = fgUUID
            }
            
            guard let sharingGroupUUID = aggregatedGroup[0].sharingGroupUUID else {
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
        
        let (_, errors) = aggregatedGroups.synchronouslyRun(apply: apply)
        if errors.count > 0 {
            return errors[0]
        }
        else {
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
    
    // Remove file uploads (DeferredUpload, Upload's) corresponding to these deletions. They are not relevant any more given that we're doing deletions.
    func pruneFileUploads(deferredFileDeletions: [DeferredUpload]) -> Bool {
        guard deferredFileDeletions.count > 0 else {
            return true
        }
        
        func prune() -> Bool {
            // Removals for DeferredUpload's with file groups.

            let deferredDeletionsWithFileGroups =
                deferredFileDeletions.filter {$0.fileGroupUUID != nil}
                
            for deferredDeletion in deferredDeletionsWithFileGroups {
                guard let fileGroupUUID = deferredDeletion.fileGroupUUID else {
                    return false
                }
                
                // Lookup any DeferredUpload file upload changes for this file group. Given that we're deleting the file group the upload changes are stale and not useful any more.
                let key1 = DeferredUploadRepository.LookupKey.fileGroupUUIDWithStatus(
                    fileGroupUUID: fileGroupUUID, status: .pendingChange)
                guard case .removed(let numberDeferredRemoved) = deferredUploadRepo.remove(key: key1) else {
                    return false
                }
                
                Log.info("Removed \(numberDeferredRemoved) DeferredUpload's for upload file changes for file group: \(fileGroupUUID)")
                
                // Now, do that corresponding action for Upload records. Any upload records representing file upload changes for files in this file group should also be removed-- they are not relevant any more given that we're removing the file group.
                let key2 = UploadRepository.LookupKey.fileGroupUUIDWithStatus(
                    fileGroupUUID: fileGroupUUID,
                    status: .vNUploadFileChange)
                guard case .removed(let numberUploadsRemoved) = uploadRepo.remove(key: key2) else {
                    return false
                }
                
                Log.info("Removed \(numberUploadsRemoved) Upload's for upload file changes for file group: \(fileGroupUUID)")
            } // end for

            // Removals for DeferredUpload's without file groups.

            let deferredDeletionsWithoutFileGroups = deferredFileDeletions.filter {$0.fileGroupUUID == nil}
            var deferredIdsForFileChangeUploads = [Int64]()
            
            for deferredDeletion in deferredDeletionsWithoutFileGroups {
                // Get the deletion Upload associated with this `deferredDeletion`
                let key1 = UploadRepository.LookupKey.deferredUploadId(deferredDeletion.deferredUploadId)
                guard case .found(let model) = uploadRepo.lookup(key: key1, modelInit: Upload.init), let uploadDeletion = model as? Upload else {
                    return false
                }
                
                // Lookup any file change Upload's associated the deletion's fileUUID
                let key2 =  UploadRepository.LookupKey.fileGroupUUIDWithStatus(fileGroupUUID: uploadDeletion.fileUUID, status: .vNUploadFileChange)
                guard let vNFileFileChangeUploads = uploadRepo.lookupAll(key: key2, modelInit: Upload.init) else {
                    return false
                }
                
                // Keep track of the deferredUploadId for these file Upload's and remove them.
                for vNFileChangeUpload in vNFileFileChangeUploads {
                    if let deferredUploadId = vNFileChangeUpload.deferredUploadId {
                        deferredIdsForFileChangeUploads += [deferredUploadId]
                    }
                    
                    let key = UploadRepository.LookupKey.uploadId(vNFileChangeUpload.uploadId)
                    guard case .removed = uploadRepo.remove(key: key) else {
                        return false
                    }
                }
            } // end for
            
            // Get rid of any non-distinct deferredUploadId's for file DeferredUpload's
            deferredIdsForFileChangeUploads = Array(Set<Int64>(deferredIdsForFileChangeUploads))
            
            // Remove these DeferredUpload's-- for file change uploads.
            for deferredIdForFileChangeUpload in deferredIdsForFileChangeUploads {
                let key = DeferredUploadRepository.LookupKey.deferredUploadId(deferredIdForFileChangeUpload)
                guard case .removed = deferredUploadRepo.remove(key: key) else {
                    return false
                }
            }
            
            return true
        } // end prune
        
        guard db.startTransaction() else {
            return false
        }
        
        guard prune() else {
            _ = db.rollback()
            return false
        }
        
        guard db.commit() else {
            _ = db.rollback()
            return false
        }
        
        return true
    }
}
