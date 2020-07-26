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

        guard let deferredUploads = deferredUploadRepo.select(rowsWithStatus: .pending) else {
            Log.error("Failed setting up select to get deferred uploads")
            try releaseLock()
            throw Errors.failedToGetDeferredUploads
        }
        
        guard deferredUploads.count > 0 else {
            Log.debug("No deferred uploads to process")
            try releaseLock()
            return
        }
        
        let nonUniqueSharingGroupUUIDs = deferredUploads.compactMap {$0.sharingGroupUUID}
        guard nonUniqueSharingGroupUUIDs.count == deferredUploads.count else {
            Log.error("Could not get nonUniqueSharingGroupUUIDs")
            try releaseLock()
            throw Errors.failedToGetNonUniqueSharingGroupUUIDs
        }
        
        Log.info("About to start async processing.")

        // Processes multiple rows in DeferredUpload when they refer to the same fileGroupUUID together. (Except for those with a nil fileGroupUUID-- which are processed independently).
        
        DispatchQueue.global().async {
            self.process(deferredUploads: deferredUploads) { error in
                try? self.releaseLock()
                
                if let error = error {
                    self.recordGlobalError(error)
                    Log.error("Failed: \(error)")
                }
                else {
                    Log.info("Succeeded!")
                }
                
                Log.debug("Calling run delegate method: \(String(describing: error))")
                
                // Don't put `self` into this as the `object`-- get a failing conversion error to NSObject
                let notification = Notification(name: Self.uploaderRunCompleted, object: nil, userInfo: [Self.errorKey: error as Any])
                
                NotificationCenter.default.post(notification)

                self.delegate?.run(completed: self, error: error)
            }
        }
    }
    
    private func recordGlobalError(_ error: Error) {
    }
    
    // Assumes all `deferredUploads` have a sharingGroupUUID.
    private func process(deferredUploads: [DeferredUpload], completion: @escaping (Swift.Error?)->()) {
    
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
