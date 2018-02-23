//
//  UserController+Extras.swift
//  Server
//
//  Created by Christopher G Prince on 2/21/18.
//

import Foundation
import LoggerAPI

extension UserController {
    func createInitialFileForOwningUser(cloudFileName: String, cloudFolderName: String?, dataForFile:Data, cloudStorage: CloudStorage, completion: @escaping (_ success: Bool)->()) {
        
        Log.info("Initial user file being sent to cloud storage: \(cloudFileName)")
    
        let options = CloudStorageFileNameOptions(cloudFolderName: cloudFolderName, mimeType: "text/plain")
    
        cloudStorage.uploadFile(cloudFileName:cloudFileName, data: dataForFile, options:options) { result in
        
            switch result {
            case .success:
                completion(true)
                
            case .failure(let error):
                // It's possible the file was successfully uploaded, but we got an error anyways. Delete it.
                cloudStorage.deleteFile(cloudFileName: cloudFileName, options: options) { _ in
                    // Ignore any error from deletion. We've alread got an error.
                    
                    Log.error("Could not upload initial file: error: \(error)")
                    completion(false)
                }
            }
        }
    }
}
