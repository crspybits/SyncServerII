import Foundation
import LoggerAPI
import ChangeResolvers

// Processes all entries in DeferredUpload as a unit.

class Uploader {
    enum UploaderError: Error {
        case failedInit
        case failedConnectingDatabase
        case failedToGetDeferredUploads
        case noFileGroupUUID
        case hasFileGroupUUID
        case notAllInGroupHaveSameFileGroupUUID
        case failedStartingTransaction
        case deferredUploadIds
        case couldNotGetAllUploads
        case couldNotGetFileUUIDs
        case couldNotLookupFileUUID
        case couldNotLookupResolver
    }
    
    private let db: Database
    private let manager: ChangeResolverManager
    private let lockName = "Uploader"
    private let uploadRepo:UploadRepository
    private let fileIndexRepo:FileIndexRepository

    init(manager: ChangeResolverManager) throws {
        // Need a separate database connection-- to have a separate transaction to acquire lock.
        guard let db = Database() else {
            throw UploaderError.failedInit
        }
        
        self.db = db
        self.manager = manager
        self.uploadRepo = UploadRepository(db)
        self.fileIndexRepo = FileIndexRepository(db)
    }
    
    private func release() throws {
        try db.releaseLock(lockName: lockName)
    }
    
    // Check if there is uploading to do. Uses a lock so it is safe *across* instances of the server. i.e., there will be at most one instance of this running across server instances. Runs asynchronously if it can get the lock.
    func run(sharingGroupUUID: String) throws {
        // Holding a lock here so that, across server instances, at most one Uploader can be running at one time.
        // TODO: Need to also start a transaction.
        guard try db.getLock(lockName: lockName) else {
            return
        }
        
        let deferredUploadRepo = DeferredUploadRepository(db)
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
                try self.process(sharingGroupUUID: sharingGroupUUID, deferredUploads: deferredUploads)
            } catch let error {
                Log.error("\(error)")
            }
        }
    }
    
    func process(sharingGroupUUID: String, deferredUploads: [DeferredUpload]) throws {
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
            
            try applyDeferredUploads(sharingGroupUUID: sharingGroupUUID, fileGroupUUID: fileGroupUUID, deferredUploads: aggregatedGroup)
        }

        for noFileGroupUUID in noFileGroupUUIDs {
            try Self.applyWithNoFileGroupUUID(deferredUpload: noFileGroupUUID)
        }
    }
    
    // Process a deferred upload with no fileGroupUUID
    static func applyWithNoFileGroupUUID(deferredUpload: DeferredUpload) throws {
        guard deferredUpload.fileGroupUUID == nil else {
            throw UploaderError.hasFileGroupUUID
        }
        
    }
    
    // Process a group of deferred uploads, all with the same fileGroupUUID
    // All DeferredUploads given must be in the fileGroupUUID given.
    func applyDeferredUploads(sharingGroupUUID: String, fileGroupUUID: String, deferredUploads: [DeferredUpload]) throws {
        guard deferredUploads.count > 0 else {
            return
        }
        
        guard (deferredUploads.filter {$0.fileGroupUUID == fileGroupUUID}).count == deferredUploads.count else {
            throw UploaderError.notAllInGroupHaveSameFileGroupUUID
        }
        
        // Each DeferredUpload corresponds to one or more Upload record.
        /* Here's the algorithm:
            0) Open the database transaction.
            1) Need to get the Account for the owner for this fileGroupUUID.
            2) let allUploads = all of the Upload records corresponding to these DeferredUpload's.
            3) let fileUUIDs = the set of unique fileUUID's within allUploads.
            4) let uploads(fileUUID) be the set of Upload's for a given fileUUID within fileUUIDs, i.e., within allUploads.
            5) for fileUUID in fileUUIDs {
                 let uploadsForFileUUID = uploads(fileUUID)
                 Get the change resolver for this fileUUID from the FileIndex
                 Read the file indicated by fileUUID from cloud storage.
                 for upload in uploadsForFileUUID {
                   Apply the change in upload to the file data using the change resolver.
                 }
                 Write the file data for the updated file back to cloud storage.
               }
            6) Do the update of the FileIndex based on these DeferredUpload records.
            7) Remove these DeferredUpload from the database.
            8) End the database transaction.
         */
         
        guard db.startTransaction() else {
            throw UploaderError.failedStartingTransaction
        }
        
        let deferredUploadIds = deferredUploads.compactMap{$0.deferredUploadId}
        guard deferredUploads.count == deferredUploadIds.count else {
            throw UploaderError.deferredUploadIds
        }
        
        guard let allUploads = UploadRepository(db).select(forDeferredUploadIds: deferredUploadIds) else {
            throw UploaderError.couldNotGetAllUploads
        }
        
        let fileUUIDs = allUploads.compactMap{$0.fileUUID}
        guard fileUUIDs.count == allUploads.count else {
            throw UploaderError.couldNotGetFileUUIDs
        }
        
        func uploads(fileUUID: String) -> [Upload] {
            allUploads.filter{$0.fileUUID == fileUUID}
        }
        
        // let result = FileController.getOwningAccountFor(sharingGroupUUID: sharingGroupUUID, fileUUID: fileUUID, from: fileIndexRepo, db: db, accountManager: accountManager)
        
        func changeResolver(forFileUUID fileUUID: String) throws -> ChangeResolver.Type {
            let key = FileIndexRepository.LookupKey.primaryKeys(sharingGroupUUID: sharingGroupUUID, fileUUID: fileUUID)
            let result = fileIndexRepo.lookup(key: key, modelInit: FileIndex.init)
            guard case .found(let model) = result,
                let fileIndex = model as? FileIndex,
                let changeResolverName = fileIndex.changeResolverName else {
                throw UploaderError.couldNotLookupFileUUID
            }
            
            guard let resolverType = manager.getResolverType(changeResolverName) else {
                throw UploaderError.couldNotLookupResolver
            }
            
            return resolverType
        }
        
        for fileUUID in fileUUIDs {
            let uploadsForFileUUID = uploads(fileUUID: fileUUID)
            let resolver = try changeResolver(forFileUUID: fileUUID)
            
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
