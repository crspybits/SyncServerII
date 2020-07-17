import Foundation
import LoggerAPI

// Processes all entries in DeferredUpload as a unit.

class Uploader {
    enum UploaderError: Error {
        case alreadySetup
        case failedConnectingDatabase
        case failedToGetDeferredUploads
        case noFileGroupUUID
        case hasFileGroupUUID
        case notAllInGroupHaveSameFileGroupUUID
    }
    
    private let db: Database
    private let manager: ChangeResolverManager
    private static var session: Uploader!
    static let lockName = "Uploader"
    
    static func setup(manager: ChangeResolverManager) throws {
        guard session == nil else {
            throw UploaderError.alreadySetup
        }
        
        // Need a separate database connection-- to have a separate transaction to acquire lock.
        guard let db = Database() else {
            throw UploaderError.failedConnectingDatabase
        }
        
        self.session = Uploader(db: db, manager: manager)
    }
    
#if DEBUG
    // For testing.
    static func reset() {
        session = nil
    }
#endif

    private init(db: Database, manager: ChangeResolverManager) {
        self.db = db
        self.manager = manager
    }
    
    static func release() throws {
        try session.db.releaseLock(lockName: lockName)
    }
    
    func release() throws {
        try Self.release()
    }
    
    // Check if there is uploading to do. Uses a lock so it is safe *across* instances of the server. i.e., there will be at most one instance of this running across server instances. Runs asynchronously if it can get the lock.
    static func run() throws {
        // Holding a lock here so that, across server instances, at most one Uploader can be running at one time.
        // TODO: Need to also start a transaction.
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
            do {
                try session.process(deferredUploads: deferredUploads)
            } catch let error {
                Log.error("\(error)")
            }
        }
    }
    
    func process(deferredUploads: [DeferredUpload]) throws {
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
        
        let aggregatedGroups = Self.aggregateDeferredUploads(withFileGroupUUIDs: withFileGroupUUIDs)
        for aggregatedGroup in aggregatedGroups {
            guard let fileGroupUUID = aggregatedGroup[0].fileGroupUUID else {
                throw UploaderError.noFileGroupUUID
            }
            
            try applyDeferredUploads(fileGroupUUID: fileGroupUUID, deferredUploads: aggregatedGroup)
        }

        for noFileGroupUUID in noFileGroupUUIDs {
            try applyWithNoFileGroupUUID(deferredUpload: noFileGroupUUID)
        }
    }
    
    // Process a deferred upload with no fileGroupUUID
    func applyWithNoFileGroupUUID(deferredUpload: DeferredUpload) throws {
        guard deferredUpload.fileGroupUUID == nil else {
            throw UploaderError.hasFileGroupUUID
        }
        
    }
    
    // Process a group of deferred uploads, all with the same fileGroupUUID
    func applyDeferredUploads(fileGroupUUID: String, deferredUploads: [DeferredUpload]) throws {
        guard deferredUploads.count > 0 else {
            return
        }
        
        guard (deferredUploads.filter {$0.fileGroupUUID == fileGroupUUID}).count == deferredUploads.count else {
            throw UploaderError.notAllInGroupHaveSameFileGroupUUID
        }
        
        // Each DeferredUpload corresponds to one or more Upload record.
        /* Here's the algorithm:
            0) Open the database transaction.
            1) let allUploads = all of the Upload records corresponding to these DeferredUpload's.
            2) let fileUUIDs = the set of unique fileUUID's within allUploads.
            3) let uploads(fileUUID) be the set of Upload's for a given fileUUID within fileUUIDs.
            4) for fileUUID in fileUUIDs {
                 let uploadsForFileUUID = uploads(fileUUID)
                 Get the change resolver for this fileUUID from the FileIndex
                 Read the file indicated by fileUUID from cloud storage.
                 for upload in uploadsForFileUUID {
                   Apply the change in upload to the file data using the change resolver.
                 }
                 Write the file data for the updated file back to cloud storage.
               }
            5) Do the update of the FileIndex based on these DeferredUpload records.
            6) Remove these DeferredUpload from the database.
            7) End the database transaction.
         */
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
