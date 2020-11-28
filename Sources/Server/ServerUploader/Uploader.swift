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

protocol PeriodicUploaderDelegate: AnyObject {
    func resetPeriodicUploader(_ uploader: Uploader)
}

protocol UploaderServices {
    var accountManager: AccountManager {get}
    var changeResolverManager: ChangeResolverManager {get}
    var mockStorage: MockStorage {get}
}

class UploaderHelpers: UploaderServices {
    let accountManager: AccountManager
    let changeResolverManager: ChangeResolverManager
    lazy var mockStorage = MockStorage()
    
    init(accountManager: AccountManager, changeResolverManager: ChangeResolverManager) {
        self.accountManager = accountManager
        self.changeResolverManager = changeResolverManager
    }
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
        case couldNotUpdateDeferredUploads
        case failedStartingDatabaseTransaction
        case failedCommittingDatabaseTransaction
        case couldNotGetFileGroup
    }
    
    let services: UploaderServices
    private let lockName = "Uploader"
    
    // Only set the following database-related members in getDbConnection()
    
    // Need a separate database connection-- to have a separate transaction and to acquire lock.
    private(set) var _db: Database!
    
    // Need separate repo references because these depend on a database connection, and we have separate db connection opened here.
    private(set) var deferredUploadRepo:DeferredUploadRepository!
    private(set) var uploadRepo:UploadRepository!
    private(set) var fileIndexRepo:FileIndexRepository!
    private(set) var userRepo: UserRepository!
    
    // For testing
    weak var delegate: UploaderDelegate?
    
    static let debugAlloc = DebugAlloc(name: "Uploader")

    init(services: UploaderServices, delegate: PeriodicUploaderDelegate?) {
        self.services = services
        
        // Defering connecting to database until actual usage of Uploader methods (and not doing it in the constructor) because (a) we need separate connections per request because use of db connections are not thread safe, and (b) because db connections are dropped after a period of time.
        // We get separate connections per request because of the way request processing is architected and uses the Uploader. More specifically, the Uploader is constructed *per request*.
        // Note that we should not have a problem with too many connections open due to this db connection because the first connnection that gets the lock will cause the other connections to last only for a brief period-- because they will not also be able to get the lock.
        Self.debugAlloc.create()
        
        delegate?.resetPeriodicUploader(self)
    }
    
    deinit {
        Log.debug("Uploader: deinit")
        Self.debugAlloc.destroy()
    }
    
    // If there is no current db connection, opens one. If there is, returns it.
    // Only the first call to this can fail.
    func getDbConnection() throws -> Database {
        if let db = _db {
            return db
        }

        guard let db = Database() else {
            throw Errors.failedConnectingDatabase
        }
        
        self._db = db
        self.deferredUploadRepo = DeferredUploadRepository(db)
        self.uploadRepo = UploadRepository(db)
        self.fileIndexRepo = FileIndexRepository(db)
        self.userRepo = UserRepository(db)
        
        return _db
    }
        
    private func getLock() throws -> Bool {
        return try getDbConnection().getLock(lockName: lockName)
    }
    
    private func releaseLock() throws {
        try getDbConnection().releaseLock(lockName: lockName)
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
        
        // Get `pendingDeletions` across all users. The `Uploader` works across all users-- and this is OK because of the mutex lock.
        guard let deferredFileDeletions = deferredUploadRepo.select(rowsWithStatus: [.pendingDeletion]) else {
            Log.error("Failed setting up select to get deferred upload deletions")
            try releaseLock()
            throw Errors.failedToGetDeferredUploads
        }
        
        // Must do pruning based on deletions before fetching the deferred file changes. Because the pruning may remove some of the deferred file changes.
        guard pruneFileUploads(deferredFileDeletions: deferredFileDeletions) else {
            Log.error("Failed pruning file uploads.")
            // TODO(https://github.com/SyncServerII/ServerMain/issues/9)
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
                Log.error("\(error)")
                self.finishRun(message: "processFileDeletions", error: error)
                return
            }

            self.processFileChanges(deferredUploads: deferredFileChangeUploads) { [weak self] error in
                guard let self = self else { return }
                if let error = error {
                    Log.error("\(error); deferredFileChangeUploads: \(deferredFileChangeUploads)")
                }
                self.finishRun(message: "processFileChanges", error: error)
            }
        }
    }
    
    private func finishRun(message: String, error: Error?) {
        try? releaseLock()

        if let error = error {
            recordGlobalError(error)
            Log.error("\(message): Failed: \(error)")
        }
        else {
            Log.info("\(message): Succeeded!")
        }
        
        Log.debug("\(message): Calling run delegate method: \(String(describing: error))")
        
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
                Log.error("applyDeferredUploads: with file groups: \(error)")
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
    private func applyDeferredUploads(aggregatedGroups: [[DeferredUpload]], withFileGroupUUID: Bool) -> Error? {
        var applier: ApplyDeferredUploads!

        func apply(aggregatedGroup: [DeferredUpload], completion: @escaping (Swift.Result<Void, Error>) -> ()) {
        
            guard aggregatedGroup.count > 0 else {
                Log.error("applyDeferredUploads: no groups")
                completion(.failure(Errors.noGroups))
                return
            }

            var fileGroupUUID: String?
            if withFileGroupUUID {
                guard let fgUUID = aggregatedGroup[0].fileGroupUUID else {
                    Log.error("applyDeferredUploads: missingGroupUUID")
                    completion(.failure(Errors.missingGroupUUID))
                    return
                }
                
                fileGroupUUID = fgUUID
            }
            
            guard let sharingGroupUUID = aggregatedGroup[0].sharingGroupUUID else {
                Log.error("applyDeferredUploads: missing sharingGroupUUID")
                completion(.failure(Errors.missingGroupUUID))
                return
            }
            
            do {
                // `applier.run` executes asynchronously. Need to retain the applier.
                applier = try ApplyDeferredUploads(sharingGroupUUID: sharingGroupUUID, fileGroupUUID: fileGroupUUID, deferredUploads: aggregatedGroup, services: services, db: try getDbConnection())
            } catch let error {
                completion(.failure(error))
                return
            }
            
            guard applier != nil else {
                Log.error("applyDeferredUploads: failedApplyDeferredUploads")
                completion(.failure(Errors.failedApplyDeferredUploads))
                return
            }
                        
            applier.run { error in
                if let error = error {
                    Log.error("applyDeferredUploads: run: \(error)")
                    completion(.failure(error))
                    return
                }
                completion(.success(()))
            }
        }
        
        let (_, errors) = aggregatedGroups.synchronouslyRun(apply: apply)
        if errors.count > 0 {
            Log.error("synchronouslyRun: \(errors[0])")
            return errors[0]
        }
        else {
            return nil
        }
    }

    // Each DeferredUpload *must* have a non-nil fileGroupUUID. The ordering of the groups in the result is not well defined.
    // Each sub-array in result has the same fileGroupUUID
    static func aggregateFileGroupUUIDs(deferredUploads: [DeferredUpload]) ->  [[DeferredUpload]] {
        return Partition.array(deferredUploads, using: \.fileGroupUUID)
    }

    // Each DeferredUpload *must* have a non-nil sharingGroupUUID. The ordering of the groups in the result is not well defined.
    // Each sub-array in result has the same sharingGroupUUID
    static func aggregateSharingGroupUUIDs(deferredUploads: [DeferredUpload]) ->  [[DeferredUpload]] {
        return Partition.array(deferredUploads, using: \.sharingGroupUUID)
    }
    
    // Remove file uploads (DeferredUpload, Upload's) corresponding to these deletions. They are not relevant any more given that we're doing deletions.
    // If `deferredFileDeletions` is empty, this returns immediately.
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
                // TODO/DeferredUpload: Test the status change.
                let key1 = DeferredUploadRepository.LookupKey.fileGroupUUIDWithStatus(
                    fileGroupUUID: fileGroupUUID, status: .pendingChange)
                let newStatus = DeferredUploadStatus.completed.rawValue
                guard let updateAllResult = deferredUploadRepo.updateAll(key: key1, updates: [DeferredUpload.statusKey: .string(newStatus)]) else {
                    Log.error("Could not update status: \(key1)")
                    return false
                }

                Log.info("Changed status to \(newStatus) for \(updateAllResult) DeferredUpload's for upload file changes for file group: \(fileGroupUUID)")
                
                // Now, do that corresponding action for Upload records. Any upload records representing file upload changes for files in this file group should also be removed-- they are not relevant any more given that we're removing the file group.
                let key2 = UploadRepository.LookupKey.fileGroupUUIDWithState(
                    fileGroupUUID: fileGroupUUID,
                    state: .vNUploadFileChange)
                guard case .removed(let numberUploadsRemoved) = uploadRepo.remove(key: key2) else {
                    return false
                }
                
                Log.info("Removed \(numberUploadsRemoved) Upload's for upload file changes for file group: \(fileGroupUUID)")
            } // end for

            // Removals for DeferredUpload's without file groups.

            let deferredDeletionsWithoutFileGroups = deferredFileDeletions.filter {$0.fileGroupUUID == nil}
            var deferredIdsForFileChangeUploads = [Int64]()
            
            for deferredDeletion in deferredDeletionsWithoutFileGroups {
                // TODO(https://github.com/SyncServerII/ServerMain/issues/8)
                // Get the deletion Upload associated with this `deferredDeletion`
                let key1 = UploadRepository.LookupKey.deferredUploadId(deferredDeletion.deferredUploadId)
                guard case .found(let model) = uploadRepo.lookup(key: key1, modelInit: Upload.init), let uploadDeletion = model as? Upload else {
                    Log.error("Could not lookup: \(key1)")
                    return false
                }
                
                Log.debug("without file group: \(key1)")
                
                // Lookup any file change Upload's associated with the deletion's fileUUID
                let key2 =  UploadRepository.LookupKey.fileUUIDWithState(fileUUID: uploadDeletion.fileUUID, state: .vNUploadFileChange)
                guard let vNFileFileChangeUploads = uploadRepo.lookupAll(key: key2, modelInit: Upload.init) else {
                    Log.error("Could not lookupAll: \(key2)")
                    return false
                }
                
                Log.debug("vNFileFileChangeUploads: \(vNFileFileChangeUploads)")
                
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
            } // end for: deferredDeletionsWithoutFileGroups
            
            // Get rid of any non-distinct deferredUploadId's for file DeferredUpload's
            deferredIdsForFileChangeUploads = Array(Set<Int64>(deferredIdsForFileChangeUploads))
            
            // Remove these DeferredUpload's-- for file change uploads. These have been pruned because there is a deletion for the same file.
            // TODO/DeferredUpload: Test the status change.
            for deferredIdForFileChangeUpload in deferredIdsForFileChangeUploads {
                guard deferredUploadRepo.update(indexId: deferredIdForFileChangeUpload, with: [DeferredUpload.statusKey: .string(DeferredUploadStatus.completed.rawValue)]) else {
                    return false
                }
            }
            
            return true
        } // end prune
        
        let db: Database
        do {
            db = try getDbConnection()
        } catch let error {
            Log.error("\(error)")
            return false
        }
        
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
