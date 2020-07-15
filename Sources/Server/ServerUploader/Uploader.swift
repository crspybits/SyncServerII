import Foundation

// Processes all entries in DeferredUpload as a unit.

// Question: Can this create a database transaction?

class Uploader {
    enum UploaderError: Error {
        case alreadySetup
        case failedConnectingDatabase
    }
    
    private let db: Database
    private let manager: ChangeResolverManager
    private static var session: Uploader!
    
    static func setup(manager: ChangeResolverManager) throws {
        guard session == nil else {
            throw UploaderError.alreadySetup
        }
        
        guard let db = Database() else {
            throw UploaderError.failedConnectingDatabase
        }
        
        self.session = Uploader(db: db, manager: manager)
    }
    
    private init(db: Database, manager: ChangeResolverManager) {
        self.db = db
        self.manager = manager
    }
    
    // Check if there is uploading to do. Uses a lock so it is safe *across* instances of the server. i.e., there will be at most one instance of this running across server instances.
    static func run() {
        // Get lock
        
        // Get rows from DeferredUpload
        
        // Sometimes multiple rows in DeferredUpload may refer to the same fileGroupUUID-- so need to process those together.
        
        // For
    }
}
