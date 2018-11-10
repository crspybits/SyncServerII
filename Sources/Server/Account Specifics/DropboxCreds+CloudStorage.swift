//
//  DropboxCreds+CloudStorage.swift
//  Server
//
//  Created by Christopher G Prince on 12/10/17.
//

import Foundation
import SyncServerShared
import LoggerAPI
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
        case nilCheckSum
        case badJSONResult
        case couldNotGetCheckSum
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
        
        self.apiCall(method: "POST", path: "/2/files/get_metadata", additionalHeaders: basicHeaders(), body: .string(body), expectedFailureBody: .json) { (apiResult, statusCode, responseHeaders) in
        
            if self.revokedAccessToken(result: apiResult, statusCode: statusCode) {
                completion(.accessTokenRevokedOrExpired)
                return
            }
            
            Log.debug("apiResult: \(String(describing: apiResult)); statusCode: \(statusCode)")

            guard statusCode == HTTPStatusCode.OK || statusCode?.rawValue == DropboxCreds.requestFailureCode else {
                completion(.failure(DropboxError.badStatusCode(statusCode)))
                return
            }
            
            guard let apiResult = apiResult else {
                completion(.failure(DropboxError.nilAPIResult))
                return
            }
            
            guard case .dictionary(let dictionary) = apiResult else {
                completion(.failure(DropboxError.badJSONResult))
                return
            }
            
            // For file not found error, gives:
            // "error": [".tag": "path", "path": [".tag": "not_found"]]
            
            if let _ = dictionary["id"] {
                completion(.success(true))
            }
            else if let error = dictionary["error"] as? [String: Any],
                let path = error["path"] as? [String: Any],
                let tag = path[".tag"] as? String,
                tag == "not_found" {
                completion(.success(false))
            }
            else {
                completion(.failure(DropboxError.unknownError))
            }
        }
    }
    
    // String in successful result is checksum.
    func uploadFile(withName fileName: String, data:Data, completion:@escaping (Result<String>)->()) {
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
            
        self.apiCall(method: "POST", baseURL: "content.dropboxapi.com", path: "/2/files/upload", additionalHeaders: headers, body: .data(data), expectedFailureBody: .json) {[unowned self] (apiResult, statusCode, responseHeaders) in
            
            if self.revokedAccessToken(result: apiResult, statusCode: statusCode) {
                completion(.accessTokenRevokedOrExpired)
                return
            }

            guard statusCode == HTTPStatusCode.OK else {
                completion(.failure(DropboxError.badStatusCode(statusCode)))
                return
            }
            
            guard let apiResult = apiResult else {
                completion(.failure(DropboxError.nilAPIResult))
                return
            }
            
            guard case .dictionary(let dictionary) = apiResult else {
                completion(.failure(DropboxError.badJSONResult))
                return
            }

            if let idJson = dictionary["id"] as? String,
                idJson != "",
                let checkSum = dictionary["content_hash"] as? String {
                completion(.success(checkSum))
            }
            else {
                completion(.failure(DropboxError.couldNotGetCheckSum))
            }
        }
    }
    
    // See https://github.com/dropbox/dropbox-sdk-obj-c/issues/83
    func revokedAccessToken(result: APICallResult?, statusCode: HTTPStatusCode?) -> Bool {
        /* ["error_summary": "invalid_access_token/...",
            "error":
                [".tag": "invalid_access_token"]
            ]
        */
        
        if statusCode == HTTPStatusCode.unauthorized,
            case .dictionary(let dict)? = result,
            let tag = dict["error"] as? [String: Any],
            let message = tag[".tag"] as? String,
            message == "invalid_access_token" {
            return true
        }
        else {
            return false
        }
    }
}

extension DropboxCreds : CloudStorage {
    enum UploadFileError : Swift.Error {
        case fileCheckFailed(Swift.Error)
        case alreadyUploaded
    }
    
    func uploadFile(cloudFileName:String, data:Data, options:CloudStorageFileNameOptions? = nil, completion:@escaping (Result<String>)->()) {
        
        // First, look to see if the file exists on Dropbox. Don't want to upload it more than once.

        checkForFile(fileName: cloudFileName) {[unowned self] result in
            switch result {
            case .failure(let error):
                completion(.failure(UploadFileError.fileCheckFailed(error)))
            case .accessTokenRevokedOrExpired:
                completion(.accessTokenRevokedOrExpired)
            case .success(let found):
                if found {
                   // Don't need to upload it again.
                    completion(.failure(CloudStorageError.alreadyUploaded))
                }
                else {
                    self.uploadFile(withName: cloudFileName, data: data) { result in
                        completion(result)
                    }
                }
            }
        }
    }
    
    func downloadFile(cloudFileName:String, options:CloudStorageFileNameOptions? = nil, completion:@escaping (DownloadResult)->()) {
        
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
        
        // "The response body contains file content, so the result will appear as JSON in the Dropbox-API-Result response header"
        // See https://www.dropbox.com/developers/documentation/http/documentation#formats

        self.apiCall(method: "POST", baseURL: "content.dropboxapi.com", path: "/2/files/download", additionalHeaders: headers, expectedSuccessBody: .data, expectedFailureBody: .json) { (apiResult, statusCode, responseHeaders) in
            
            /* Example of what is returned when a file is not found:
                HTTPStatusCode.conflict
                (["error": ["path": [".tag": "not_found"], ".tag": "path"], "error_summary": "path/not_found/"]))
                See also https://www.dropbox.com/developers/documentation/http/documentation#error-handling and
                https://www.dropboxforum.com/t5/API-Support-Feedback/Did-404-change-to-409-in-v2/td-p/208370
            */
            
            if statusCode == HTTPStatusCode.conflict,
                case .dictionary(let dict)? = apiResult,
                let path = dict["error"] as? [String: Any],
                let tag = path["path"] as? [String: Any],
                let message = tag[".tag"] as? String,
                message == "not_found" {
                
                Log.warning("Dropbox: File \(cloudFileName) not found.")
                completion(.fileNotFound)
                return
            }
            
            if self.revokedAccessToken(result: apiResult, statusCode: statusCode) {
                completion(.accessTokenRevokedOrExpired)
                return
            }
            
            guard statusCode == HTTPStatusCode.OK else {
                completion(.failure(DropboxError.badStatusCode(statusCode)))
                return
            }
            
            guard let apiResult = apiResult else {
                completion(.failure(DropboxError.nilAPIResult))
                return
            }
            
            guard let headerAPIResult = responseHeaders?["Dropbox-API-Result"], headerAPIResult.count > 0 else {
                Log.error("Could not get headerAPIResult")
                completion(.failure(DropboxError.nilCheckSum))
                return
            }
            
            guard let headerAPIResultDict = headerAPIResult[0].toJSONDictionary() else {
                Log.error("Could not convert string to JSON dict: headerAPIResultDict")
                completion(.failure(DropboxError.nilCheckSum))
                return
            }

            guard let checkSum = headerAPIResultDict["content_hash"] as? String else {
                Log.error("Could not get check sum from headerAPIResultDict")
                completion(.failure(DropboxError.nilCheckSum))
                return
            }
                        
            guard case .data(let data) = apiResult else {
                completion(.failure(DropboxError.noDataInAPIResult))
                return
            }

            let downloadResult:DownloadResult = .success(data: data, checkSum: checkSum)
            completion(downloadResult)
        }
    }
    
    func deleteFile(cloudFileName:String, options:CloudStorageFileNameOptions? = nil,
        completion:@escaping (Result<()>)->()) {
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
        
        self.apiCall(method: "POST", path: "/2/files/delete_v2", additionalHeaders: headers, body: .string(body), expectedFailureBody: .json) { (apiResult, statusCode, responseHeaders) in
        
            if self.revokedAccessToken(result: apiResult, statusCode: statusCode) {
                completion(.accessTokenRevokedOrExpired)
                return
            }
            
            guard statusCode == HTTPStatusCode.OK else {
                completion(.failure(DropboxError.badStatusCode(statusCode)))
                return
            }
            
            guard let apiResult = apiResult else {
                completion(.failure(DropboxError.nilAPIResult))
                return
            }
            
            guard case .dictionary(let dictionary) = apiResult else {
                completion(.failure(DropboxError.badJSONResult))
                return
            }

            if let metaData = dictionary["metadata"] as? [String: Any],
                let idJson = metaData["id"] as? String,
                idJson != "" {
                completion(.success(()))
            }
            else {
                completion(.failure(DropboxError.couldNotGetId))
            }
        }
    }
    
    func lookupFile(cloudFileName:String, options:CloudStorageFileNameOptions? = nil,
        completion:@escaping (Result<Bool>)->()) {
        
        checkForFile(fileName: cloudFileName) { result in
            completion(result)
        }
    }
}
