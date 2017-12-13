//
//  DropboxCreds+CloudStorage.swift
//  Server
//
//  Created by Christopher G Prince on 12/10/17.
//

import Foundation
import SyncServerShared
import LoggerAPI
import SwiftyJSON
import KituraNet

extension DropboxCreds {
    // Dropbox is using this https://blogs.dropbox.com/developers/2015/04/a-preview-of-the-new-dropbox-api-v2/ "But if a request fails for some call-specific reason, v1 might have returned any of 403, 404, 406, 411, etc. API v2 will always return a 409 status code with a stable and documented error identifier in the body. We chose 409 because, unlike many other error codes, it doesn’t have any specific meaning in the HTTP spec. This ensures that HTTP intermediaries, such as proxies or client libraries, will relay it along untouched."
    static let requestFailureCode = 409
    
    private func basicHeaders(withContentTypeHeader contentType:String = "application/json") -> [String: String] {
        var headers = [String:String]()
        headers["Authorization"] = "Bearer \(accessToken!)"
        headers["Content-Type"] = contentType
        return headers
    }
    
    enum DropboxError : Swift.Error {
        case badStatusCode(HTTPStatusCode?)
        case nilAPIResult
        case badJSONResult
        case couldNotGetFileSize
        case unknownError
        case noDataInAPIResult
        case couldNotGetId
    }
    
    // On success, Bool in result indicates whether or not the file exists.
    func checkForFile(fileName: String, completion:@escaping (Result<Bool>)->()) {
        // See https://www.dropbox.com/developers/documentation/http/documentation#files-get_metadata
        /*
         curl -X POST https://api.dropboxapi.com/2/files/get_metadata \
         --header "Authorization: Bearer " \
         --header "Content-Type: application/json" \
         --data "{\"path\": \"/Homework/math\",\"include_media_info\": false,\"include_deleted\": false,\"include_has_explicit_shared_members\": false}"
        */
        
        // It's hard to see in here, but I've put an explicit "/" before the file name. Dropbox needs this to precede file names.
        let body = "{\"path\": \"/\(fileName)\",\"include_media_info\": false,\"include_deleted\": false,\"include_has_explicit_shared_members\": false}"
        
        self.apiCall(method: "POST", path: "/2/files/get_metadata", additionalHeaders: basicHeaders(), body: .string(body), returnResultWhenNon200Code: true) { (apiResult, statusCode) in
            
            // Log.debug("apiResult: \(String(describing: apiResult))")

            guard statusCode == HTTPStatusCode.OK || statusCode?.rawValue == DropboxCreds.requestFailureCode else {
                completion(.failure(DropboxError.badStatusCode(statusCode)))
                return
            }
            
            guard let apiResult = apiResult else {
                completion(.failure(DropboxError.nilAPIResult))
                return
            }
            
            guard case .json(let jsonResult) = apiResult else {
                completion(.failure(DropboxError.badJSONResult))
                return
            }
            
            // For file not found error, gives:
            // "error": [".tag": "path", "path": [".tag": "not_found"]]
            
            if let _ = jsonResult.dictionary?["id"] {
                completion(.success(true))
            }
            else if let error = jsonResult.dictionary?["error"],
                let path = error.dictionary?["path"],
                let tag = path.dictionary?[".tag"],
                tag.string == "not_found" {
                completion(.success(false))
            }
            else {
                completion(.failure(DropboxError.unknownError))
            }
        }
    }
    
    func uploadFile(withName fileName: String, data:Data, completion:@escaping (Result<Int>)->()) {
        // https://www.dropbox.com/developers/documentation/http/documentation#files-upload
        /*
         curl -X POST https://content.dropboxapi.com/2/files/upload \
         --header "Authorization: Bearer " \
         --header "Dropbox-API-Arg: {\"path\": \"/Homework/math/Matrices.txt\",\"mode\": \"add\",\"autorename\": true,\"mute\": false}" \
         --header "Content-Type: application/octet-stream" \
         --data-binary @local_file.txt
        */
        
        var headers = basicHeaders()
        headers["Dropbox-API-Arg"] = "{\"path\": \"/\(fileName)\",\"mode\": \"add\",\"autorename\": false,\"mute\": false}"
        headers["Content-Type"] = "application/octet-stream"
            
        self.apiCall(method: "POST", baseURL: "content.dropboxapi.com", path: "/2/files/upload", additionalHeaders: headers, body: .data(data)) { (apiResult, statusCode) in
            
            guard statusCode == HTTPStatusCode.OK else {
                completion(.failure(DropboxError.badStatusCode(statusCode)))
                return
            }
            
            guard let apiResult = apiResult else {
                completion(.failure(DropboxError.nilAPIResult))
                return
            }
            
            guard case .json(let jsonResult) = apiResult else {
                completion(.failure(DropboxError.badJSONResult))
                return
            }

            if let idJson = jsonResult.dictionary?["id"],
                idJson.string != "",
                let sizeJson = jsonResult.dictionary?["size"],
                let size = sizeJson.number {
                completion(.success(Int(size)))
            }
            else {
                completion(.failure(DropboxError.couldNotGetFileSize))
            }
        }
    }
}

extension DropboxCreds : CloudStorage {
    enum UploadFileError : Swift.Error {
        case fileCheckFailed(Swift.Error)
        case alreadyUploaded
    }
    
    func uploadFile(cloudFileName:String, data:Data, options:CloudStorageFileNameOptions? = nil, completion:@escaping (Result<Int>)->()) {
        assert(options == nil)
        
        // First, look to see if the file exists on Dropbox. Don't want to upload it more than once.

        checkForFile(fileName: cloudFileName) {[unowned self] result in
            switch result {
            case .failure(let error):
                completion(.failure(UploadFileError.fileCheckFailed(error)))
            case .success(let found):
                if found {
                   // Don't need to upload it again.
                    completion(.failure(UploadFileError.alreadyUploaded))
                }
                else {
                    self.uploadFile(withName: cloudFileName, data: data) { result in
                        completion(result)
                    }
                }
            }
        }
    }
    
    func downloadFile(cloudFileName:String, options:CloudStorageFileNameOptions? = nil, completion:@escaping (Result<Data>)->()) {
    
        assert(options == nil)
    
        // https://www.dropbox.com/developers/documentation/http/documentation#files-download
        /*
        curl -X POST https://content.dropboxapi.com/2/files/download \
            --header "Authorization: Bearer " \
            --header "Dropbox-API-Arg: {\"path\": \"/Homework/math/Prime_Numbers.txt\"}"
        */
        
        // Content-Type needs to explicitly be an empty string or the request fails. Odd.
        // See https://stackoverflow.com/questions/42755495/dropbox-download-file-api-stopped-working-with-400-error
        var headers = basicHeaders(withContentTypeHeader: "")
        headers["Dropbox-API-Arg"] = "{\"path\": \"/\(cloudFileName)\"}"

        self.apiCall(method: "POST", baseURL: "content.dropboxapi.com", path: "/2/files/download", additionalHeaders: headers) { (apiResult, statusCode) in
            
            guard statusCode == HTTPStatusCode.OK else {
                completion(.failure(DropboxError.badStatusCode(statusCode)))
                return
            }
            
            guard let apiResult = apiResult else {
                completion(.failure(DropboxError.nilAPIResult))
                return
            }
            
            guard case .data(let data) = apiResult else {
                completion(.failure(DropboxError.noDataInAPIResult))
                return
            }

            completion(.success(data))
        }
    }
    
    func deleteFile(cloudFileName:String, options:CloudStorageFileNameOptions? = nil,
        completion:@escaping (Swift.Error?)->()) {
        // https://www.dropbox.com/developers/documentation/http/documentation#files-delete_v2
        /*
        curl -X POST https://api.dropboxapi.com/2/files/delete_v2 \
            --header "Authorization: Bearer " \
            --header "Content-Type: application/json" \
            --data "{\"path\": \"/Homework/math/Prime_Numbers.txt\"}"
        */
        
        var headers = basicHeaders()
        headers["Content-Type"] = "application/json"
        
        let body = "{\"path\": \"/\(cloudFileName)\"}"
        
        self.apiCall(method: "POST", path: "/2/files/delete_v2", additionalHeaders: headers, body: .string(body)) { (apiResult, statusCode) in
            
            guard statusCode == HTTPStatusCode.OK else {
                completion(DropboxError.badStatusCode(statusCode))
                return
            }
            
            guard let apiResult = apiResult else {
                completion(DropboxError.nilAPIResult)
                return
            }
            
            guard case .json(let jsonResult) = apiResult else {
                completion(DropboxError.badJSONResult)
                return
            }

            if let metaDataJson = jsonResult.dictionary?["metadata"],
                let idJson = metaDataJson.dictionary?["id"],
                idJson.string != "" {
                completion(nil)
            }
            else {
                completion(DropboxError.couldNotGetId)
            }
        }
    }
}
