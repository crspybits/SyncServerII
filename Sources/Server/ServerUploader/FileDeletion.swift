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
                Log.warning("Failed removing file: \(self.cloudFileName)")
                completion(FileDeletionError.failedDeletingFile)
                return
            }
            
            completion(nil)
        }
    }
    
    // On an error, it keeps going to try to remove the remaining files.
    static func apply(deletions: [FileDeletion]) -> [Error]? {
        func singleDeletion(deletion: FileDeletion, completion: @escaping (Swift.Result<Void, Error>) -> ()) {
            Log.debug("delete: \(deletion.cloudFileName)")
            deletion.delete { error in
                if let error = error {
                    completion(.failure(error))
                }
                else {
                    completion(.success(()))
                }
            }
        }
        
        let (_, errors) = deletions.synchronouslyRun(stopAtFirstError: false, apply: singleDeletion)
        if errors.count > 0 {
            return errors
        }
        else {
            return nil
        }
    }
}

