import Foundation

// Processes all entries in DeferredUpload as a unit.

// Question: Can this create a database transaction?

class Uploader {
    enum UploaderError: Error {
        case alreadySetup
        case failedConnectingDatabase
        case failedToGetDeferredUploads
    }
    
    private let db: Database
    private let manager: ChangeResolverManager
    private static var session: Uploader!
    static let lockName = "Uploader"
    
    static func setup(manager: ChangeResolverManager) throws {
        guard session == nil else {
            throw UploaderError.alreadySetup
        }
        
        // Need a separate database connection-- to acquire lock.
        guard let db = Database() else {
            throw UploaderError.failedConnectingDatabase
        }
        
        self.session = Uploader(db: db, manager: manager)
    }
    
    private init(db: Database, manager: ChangeResolverManager) {
        self.db = db
        self.manager = manager
    }
    
    static func release() throws {
        try session.db.releaseLock(lockName: lockName)
    }
    
    func release () throws {
        try Self.release()
    }
    
    // Check if there is uploading to do. Uses a lock so it is safe *across* instances of the server. i.e., there will be at most one instance of this running across server instances. Runs asynchronously if it can get the lock.
    static func run() throws {
        // Holding a lock here so that, across server instances, at most one Uploader can be running at one time.
        guard try session.db.getLock(lockName: lockName) else {
            return
        }
        
        let deferredUploadRepo = DeferredUploadRepository(session.db)
        guard let deferredUploads = deferredUploadRepo.select(rowsWithStatus: .pending) else {
            try release()
            throw UploaderError.failedToGetDeferredUploads
        }
        
        guard deferredUploads.count > 0 else {
            // No deferred uploads to process
            try release()
            return
        }
        
        // Sometimes multiple rows in DeferredUpload may refer to the same fileGroupUUID-- so need to process those together. (Except for those with a nil fileGroupUUID-- which are processed independently).
        DispatchQueue.global(qos: .default).async {
            session.process(deferredUploads: deferredUploads)
        }
    }
    
    func process(deferredUploads: [DeferredUpload]) {
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

        processDeferredUploadsWithNoFileGroupUUID(deferredUpload: noFileGroupUUIDs)
    }
    
    func processDeferredUploadsWithNoFileGroupUUID(deferredUpload: [DeferredUpload]) {
    }
    
    // Process a group of deferred uploads, all with the same fileGroupUUID
    func processDeferredUploads(fileGroupUUID: String, deferredUploads: [DeferredUpload]) {
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
