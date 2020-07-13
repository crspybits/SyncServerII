import Foundation

// Processes all entries in DeferredUpload as a unit.

// Question: Can this create a database transaction?

class Uploader {
    let db: Database
    
    init(db: Database) {
        self.db = db
    }
    
    // Check if there is uploading to do. Uses a lock so it is safe *across* instances of the server. i.e., there will be at most one instance of this running across server instances.
    static func run() {
        // Get lock
        
        // Get rows from DeferredUpload
        
        // Sometimes multiple rows in DeferredUpload may refer to the same fileGroupUUID-- so need to process those together.
        
        // For
    }
}
