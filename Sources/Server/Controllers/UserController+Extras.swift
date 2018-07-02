//
//  UserController+Extras.swift
//  Server
//
//  Created by Christopher G Prince on 2/21/18.
//

import Foundation
import LoggerAPI

extension UserController {
    static func createInitialFileForOwningUser(cloudFolderName: String?, cloudStorage: CloudStorage, completion: @escaping (_ success: Bool)->()) {
    
        guard let fileName = Constants.session.owningUserAccountCreation.initialFileName,
                let fileContents = Constants.session.owningUserAccountCreation.initialFileContents,
                let data = fileContents.data(using: .utf8) else {
                
            // Note: This is not an error-- the server just isn't configured to create these files for owning user accounts.
            Log.info("No file name and/or contents for initial user file.")
            completion(true)
            return
        }
        
        Log.info("Initial user file being sent to cloud storage: \(fileName)")
    
        let options = CloudStorageFileNameOptions(cloudFolderName: cloudFolderName, mimeType: "text/plain")
    
        cloudStorage.uploadFile(cloudFileName:fileName, data: data, options:options) { result in
        
            switch result {
            case .success:
                completion(true)
                
            case .failure(CloudStorageError.alreadyUploaded):
                // Not considering it an error when the initial file is already there-- user might be recreating an account.
                Log.info("Could not upload initial file: It already exists.")
                completion(true)
                
            case .failure(let error):
                // It's possible the file was successfully uploaded, but we got an error anyways. Delete it.
                cloudStorage.deleteFile(cloudFileName: fileName, options: options) { _ in
                    // Ignore any error from deletion. We've alread got an error.
                    
                    Log.error("Could not upload initial file: error: \(error)")
                    completion(false)
                }
            }
        }
    }
}
