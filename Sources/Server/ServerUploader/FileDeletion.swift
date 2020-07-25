import ServerAccount
import LoggerAPI

struct FileDeletion {
    enum FileDeletionError: Error {
        case failedDeletingFile
    }
    
    let cloudStorage: CloudStorage
    let cloudFileName: String
    let options: CloudStorageFileNameOptions
    
    func delete(completion: @escaping (Error?)->()) {
        Log.debug("Deleting file: \(self.cloudFileName)")
        cloudStorage.deleteFile(cloudFileName: cloudFileName, options: options) { result in
            switch result {
            case .success:
                Log.debug("File deleted: \(self.cloudFileName)")
            default:
                // We have done everything successfully, but we've failed on deleting the old file version. It's possible, however, that we've actually removed the old file version, but just failed getting the result.
                // In the worst case, there's a stale version of a file in cloud storage. Don't report this as an actual error, which will cause a db transaction rollback.
                Log.warning("Failed removing prior file version: \(self.cloudFileName)")
                completion(FileDeletionError.failedDeletingFile)
                return
            }
            
            completion(nil)
        }
    }
    
    // On an error, it keeps going to try to remove the remaining files. The most recent error is returned in the completion.
    static func apply(index: Int = 0, deletions: [FileDeletion], error: Error? = nil, completion: @escaping (Error?)->()) {
        guard index < deletions.count else {
            Log.debug("Removed \(deletions.count) file(s)")
            completion(error)
            return
        }
        
        let deletion = deletions[index]
        var result: Error? = error
        
        deletion.delete { error in
            if let error = error {
                result = error
            }
            
            apply(index: index + 1, deletions: deletions, error: result, completion: completion)
        }
    }
}

