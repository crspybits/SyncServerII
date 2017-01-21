//
//  FileController.swift
//  Server
//
//  Created by Christopher Prince on 1/15/17.
//
//

import Foundation
import PerfectLib
import Credentials
import CredentialsGoogle

class FileController : ControllerProtocol {
    // Don't do this setup in init so that database initalizations don't have to be done per endpoint call.
    class func setup() -> Bool {
        if case .failure(_) = UploadRepository.create() {
            return false
        }
        return true
    }
    
    init() {
    }
    
    func upload(_ request: RequestMessage, creds:Creds?, profile:UserProfile?,
        completion:@escaping (ResponseMessage?)->()) {
    
        guard let uploadRequest = request as? UploadFileRequest else {
            Log.error(message: "Did not receive UploadFileRequest")
            completion(nil)
            return
        }
        
        guard let googleCreds = creds as? GoogleCreds else {
            Log.error(message: "Could not obtain Google Creds")
            completion(nil)
            return
        }
                
        // TODO: This needs to be generalized to enabling uploads to various kinds of cloud services. E.g., including Dropbox. Right now, it's just specific to Google Drive.
        
        // TODO: Need to have streaming data from client, and send streaming data up to Google Drive.
        
        // TODO: Need to make use of Upload repository.
        
        googleCreds.uploadSmallFile(upload: uploadRequest) { error in
            if error == nil {
                let response = UploadFileResponse()
                response.size = Int64(uploadRequest.data.count)
                completion(response)
            }
            else {
                completion(nil)
            }
        }
    }
}
