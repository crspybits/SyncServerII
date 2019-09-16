//
//  MicrosofttCreds+CloudStorage.swift
//  Server
//
//  Created by Christopher G Prince on 9/7/19.
//

import Foundation
import LoggerAPI
import HeliumLogger
import KituraNet
import SyncServerShared

extension MicrosoftCreds : CloudStorage {
    enum OneDriveFailure: Swift.Error {
        case urlEncoding
        case mimeTypeEncoding
        case noAPIResult
        case noDataInAPIResult
        case couldNotDecodeError
        case otherError(ErrorResult)
        case badStatusCode(HTTPStatusCode?, ErrorResult?)
        case couldNotDecodeResult
        case couldNotGetOptions
        case couldNotGetSelf
        case fileNotFound
    }
    
    private func basicHeaders(withContentTypeHeader contentType:String = "application/json") -> [String: String] {
        var headers = [String:String]()
        headers["Authorization"] = "Bearer \(accessToken!)"
        headers["Content-Type"] = contentType
        return headers
    }
    
    func uploadFile(cloudFileName: String, data: Data, options: CloudStorageFileNameOptions?, completion: @escaping (Result<String>) -> ()) {
        guard let options = options,
            let mimeType = MimeType(rawValue: options.mimeType) else {
            completion(.failure(OneDriveFailure.couldNotGetOptions))
            return
        }
        
        checkForFile(fileName: cloudFileName) {[weak self] result in
            guard let self = self else {
                completion(.failure(OneDriveFailure.couldNotGetSelf))
                return
            }
            
            switch result {
            case .success(.fileFound):
                completion(.failure(CloudStorageError.alreadyUploaded))
                
            case .success(.fileNotFound):
                self.uploadFile(withName: cloudFileName, mimeType: mimeType, data: data, completion: completion)

            case .failure(let error):
                completion(.failure(error))
                
            case .accessTokenRevokedOrExpired:
                completion(.accessTokenRevokedOrExpired)
            }
        }
    }
    
    func downloadFile(cloudFileName: String, options: CloudStorageFileNameOptions?, completion: @escaping (DownloadResult) -> ()) {
        
        // First do a `checkForFile` to get the file's checksum.
        checkForFile(fileName: cloudFileName) {[weak self] result in
            guard let self = self else {
                completion(.failure(OneDriveFailure.couldNotGetSelf))
                return
            }
            
            switch result {
            case .success(.fileFound(let fileResult)):
                self.downloadFile(cloudFileName: cloudFileName) { result in
                    switch result {
                    case .success(let data):
                        completion(.success(
                            data: data,
                            checkSum: fileResult.file.hashes.sha1Hash))
                    case .failure(let error):
                        completion(.failure(error))
                    case .accessTokenRevokedOrExpired:
                        completion(.accessTokenRevokedOrExpired)
                    }
                }
                
            case .success(.fileNotFound):
                completion(.fileNotFound)
            case .accessTokenRevokedOrExpired:
                completion(.accessTokenRevokedOrExpired)
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }
    
    func deleteFile(cloudFileName: String, options: CloudStorageFileNameOptions?, completion: @escaping (Result<()>) -> ()) {
        deleteFile(cloudFileName: cloudFileName, completion: completion)
    }
    
    func lookupFile(cloudFileName: String, options: CloudStorageFileNameOptions?, completion: @escaping (Result<Bool>) -> ()) {
        checkForFile(fileName: cloudFileName) { result in
            switch result {
            case .success(.fileFound):
                completion(.success(true))
            case .success(.fileNotFound):
                completion(.success(false))
            case .accessTokenRevokedOrExpired:
                completion(.accessTokenRevokedOrExpired)
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }
}

// MARK: Helpers

extension MicrosoftCreds {
    func accessTokenIsRevokedOrExpired(errorResult: ErrorResult, statusCode: HTTPStatusCode?) -> Bool {

        if errorResult.error.code == MicrosoftCreds.ErrorResult.expiredAuthCode {
            return true
        }
        
        return false
    }
    
    struct ErrorResult: Decodable {
        // Assuming this response means an expired auth code
        static let expiredAuthCode = "InvalidAuthenticationToken"
        
        struct TheError: Decodable {
            let code: String
            let message: String
        }
        let error: TheError
    }
    
    var graphBaseURL: String {
        return "graph.microsoft.com/v1.0"
    }
    
    struct FileResult: Decodable {
        let id: String

        // Lots of other fields in this too.
        struct File: Decodable {
            let mimeType: String
            
            struct Hashes: Decodable {
                let quickXorHash: String
                let sha1Hash: String
            }
            
            let hashes: Hashes
        }
        
        let file: File
    }
    
    struct FileCheck: Decodable {
        let value: [FileResult]
    }
    
    enum CheckForFileResult {
        case fileNotFound
        case fileFound(FileResult)
    }
    
    func checkForFile(fileName: String, completion:@escaping (Result<CheckForFileResult>)->()) {
    
        // /me/drive/root:/{item-path}
        // https://docs.microsoft.com/en-us/onedrive/developer/rest-api/api/driveitem_get?view=odsp-graph-online
        
        let path = "/me/drive/special/approot:/\(fileName)"
        guard let encodedPath = encoded(string: path, additionalExcludedCharacters: "()''") else {
            Log.error("Failed encoding path.")
            completion(.failure(OneDriveFailure.urlEncoding))
            return
        }
        
        self.apiCall(method: "GET", baseURL: graphBaseURL, path: encodedPath, additionalHeaders: basicHeaders(), expectedSuccessBody: .data, expectedFailureBody: .data) {[weak self] apiResult, statusCode, responseHeaders in
        
            guard let self = self else {
                completion(.failure(OneDriveFailure.couldNotGetSelf))
                return
            }
            
            Log.debug("apiResult: \(String(describing: apiResult)); statusCode: \(String(describing: statusCode))")
            
            guard let apiResult = apiResult else {
                completion(.failure(OneDriveFailure.noAPIResult))
                return
            }
            
            guard case .data(let data) = apiResult else {
                completion(.failure(OneDriveFailure.noDataInAPIResult))
                return
            }
            
            let decoder = JSONDecoder()
            
            guard statusCode == HTTPStatusCode.OK else {
                guard let errorResult = try? decoder.decode(ErrorResult.self, from: data) else {
                    completion(.failure(OneDriveFailure.couldNotDecodeError))
                    return
                }
                
                guard !self.accessTokenIsRevokedOrExpired(errorResult: errorResult, statusCode: statusCode) else {
                    completion(.accessTokenRevokedOrExpired)
                    return
                }
            
                if errorResult.error.code == "itemNotFound" {
                    completion(.success(.fileNotFound))
                    return
                }

                completion(.failure(OneDriveFailure.badStatusCode(statusCode, errorResult)))
                return
            }
            
            guard let fileResult = try? decoder.decode(FileResult.self, from: data) else {
                completion(.failure(OneDriveFailure.couldNotDecodeResult))
                return
            }
            
            completion(.success(.fileFound(fileResult)))
        }
    }
    
    // I initially tried using the search-based method below for checkForFile. However, there seems to be a latency between uploading a file and being able to search for that file and find it.
#if false
    // Not using a mimeType to check for a file existing. Can OneDrive have two different files with the same file name but different mimeTypes?
    func checkForFile2(fileName: String, completion:@escaping (Result<Bool>)->()) {
       // https://docs.microsoft.com/en-us/onedrive/developer/rest-api/concepts/special-folders-appfolder?view=odsp-graph-online
        // Shows: GET /drive/special/approot:/{path}:/search
        // And that links to:
        // https://docs.microsoft.com/en-us/onedrive/developer/rest-api/api/driveitem_search?view=odsp-graph-online
        
        let path = "/me/drive/special/approot/search(q='\(fileName)')"
        guard let encodedPath = encoded(string: path, additionalExcludedCharacters: "()''") else {
            Log.error("Failed encoding path.")
            completion(.failure(OneDriveFailure.urlEncoding))
            return
        }
        
        self.apiCall(method: "GET", baseURL: graphBaseURL, path: encodedPath, additionalHeaders: basicHeaders(), expectedSuccessBody: .data, expectedFailureBody: .data) { apiResult, statusCode, responseHeaders in
        
            Log.debug("apiResult: \(String(describing: apiResult)); statusCode: \(String(describing: statusCode))")
            
            guard let apiResult = apiResult else {
                completion(.failure(OneDriveFailure.noAPIResult))
                return
            }
            
            guard case .data(let data) = apiResult else {
                completion(.failure(OneDriveFailure.noDataInAPIResult))
                return
            }
        
            guard statusCode == HTTPStatusCode.OK else {
                completion(.failure(OneDriveFailure.badStatusCode(statusCode)))
                return
            }
            
            let decoder = JSONDecoder()
            guard let fileCheckResult = try? decoder.decode(FileCheckResult.self, from: data) else {
                completion(.failure(OneDriveFailure.couldNotDecodeError))
                return
            }
            
            completion(.success(!fileCheckResult.value.isEmpty))
        }
    }
#endif

    // String in successful result is checksum.
    // This is for uploading files up to 4MB in size.
    func uploadFile(withName fileName: String, mimeType: MimeType, data:Data, completion:@escaping (Result<String>)->()) {

        // https://docs.microsoft.com/en-us/onedrive/developer/rest-api/concepts/special-folders-appfolder?view=odsp-graph-online
        // https://docs.microsoft.com/en-us/onedrive/developer/rest-api/api/driveitem_put_content?view=odsp-graph-online
        
        let path = "/me/drive/special/approot:/\(fileName):/content"
        guard let encodedPath = encoded(string: path) else {
            Log.error("Failed encoding path.")
            completion(.failure(OneDriveFailure.urlEncoding))
            return
        }
        
        guard let encodedMimeType = encoded(string: mimeType.rawValue, additionalExcludedCharacters: "/") else {
            Log.error("Failed encoding mimeType.")
            completion(.failure(OneDriveFailure.mimeTypeEncoding))
            return
        }
        
        self.apiCall(method: "PUT", baseURL: graphBaseURL, path: encodedPath, additionalHeaders: basicHeaders(withContentTypeHeader: encodedMimeType), body: .data(data), expectedSuccessBody: .data, expectedFailureBody: .data) { apiResult, statusCode, responseHeaders in
        
            Log.debug("apiResult: \(String(describing: apiResult)); statusCode: \(String(describing: statusCode))")
            
            guard let apiResult = apiResult else {
                completion(.failure(OneDriveFailure.noAPIResult))
                return
            }
            
            guard case .data(let data) = apiResult else {
                completion(.failure(OneDriveFailure.noDataInAPIResult))
                return
            }
            
            let decoder = JSONDecoder()
            
            guard statusCode == HTTPStatusCode.created || statusCode == HTTPStatusCode.OK else {
                guard let errorResult = try? decoder.decode(ErrorResult.self, from: data) else {
                    completion(.failure(OneDriveFailure.couldNotDecodeError))
                    return
                }
                
                guard !self.accessTokenIsRevokedOrExpired(errorResult: errorResult, statusCode: statusCode) else {
                    completion(.accessTokenRevokedOrExpired)
                    return
                }
                
                completion(.failure(OneDriveFailure.badStatusCode(statusCode, errorResult)))
                return
            }
            
            guard let uploadResult = try? decoder.decode(FileResult.self, from: data) else {
                completion(.failure(OneDriveFailure.couldNotDecodeResult))
                return
            }
            
            completion(.success(uploadResult.file.hashes.sha1Hash))
        }
    }
    
    /// Download the file, but don't get the checksum.
    func downloadFile(cloudFileName: String, completion: @escaping (Result<Data>) -> ()) {
    
        // https://docs.microsoft.com/en-us/onedrive/developer/rest-api/api/driveitem_get_content?view=odsp-graph-online
        // Note that this endpoint initially generates a "302 Found" response-- and I think the HTTP library I'm using must follow it because I get the downloaded file-- and not the preauthenticated link.
        
        let path = "/me/drive/special/approot:/\(cloudFileName):/content"
        guard let encodedPath = encoded(string: path) else {
            Log.error("Failed encoding path.")
            completion(.failure(OneDriveFailure.urlEncoding))
            return
        }
        
        // To not traverse the "302 Found" response redirect
        // let additionalOptions: [ClientRequest.Options] = [.maxRedirects(0)]
        let additionalOptions: [ClientRequest.Options] = []

        self.apiCall(method: "GET", baseURL: graphBaseURL, path: encodedPath, additionalHeaders: basicHeaders(), additionalOptions: additionalOptions, expectedSuccessBody: .data, expectedFailureBody: .data) { apiResult, statusCode, responseHeaders in
        
            Log.debug("apiResult: \(String(describing: apiResult)); statusCode: \(String(describing: statusCode))")
            
            guard let apiResult = apiResult else {
                completion(.failure(OneDriveFailure.noAPIResult))
                return
            }
            
            guard case .data(let data) = apiResult else {
                completion(.failure(OneDriveFailure.noDataInAPIResult))
                return
            }
            
            // When handling a 302, need to do:
            /*
            guard statusCode == HTTPStatusCode.movedTemporarily else {
                completion(.failure(OneDriveFailure.badStatusCode(statusCode)))
                return
            }
            // And then the preauthenticated download link is in here:
            let location = responseHeaders?["Location"] ?? []
            Log.debug("Location: \(location)")
            */
            
            guard statusCode == HTTPStatusCode.OK else {
                let decoder = JSONDecoder()
                guard let errorResult = try? decoder.decode(ErrorResult.self, from: data) else {
                    completion(.failure(OneDriveFailure.couldNotDecodeError))
                    return
                }
                
                guard !self.accessTokenIsRevokedOrExpired(errorResult: errorResult, statusCode: statusCode) else {
                    completion(.accessTokenRevokedOrExpired)
                    return
                }
                
                completion(.failure(OneDriveFailure.badStatusCode(statusCode, errorResult)))
                return
            }
            
            completion(.success(data))
        }
    }
    
    func deleteFile(itemId: String, completion: @escaping (Result<()>) -> ()) {
    
        // https://docs.microsoft.com/en-us/onedrive/developer/rest-api/api/driveitem_delete?view=odsp-graph-online
        // DELETE /me/drive/items/{item-id}
        
        // This deletes the entire app folder! Yike!
        // let path = "/me/drive/special/approot/items/\(itemId)"
        // I wonder if this is related to https://answers.microsoft.com/en-us/windows/forum/all/onedrive-automatically-deleting-files-from/f9582c7f-ae84-474c-b470-4e941b6682a1?page=7

        let path = "/me/drive/items/\(itemId)"
        guard let encodedPath = encoded(string: path) else {
            Log.error("Failed encoding path.")
            completion(.failure(OneDriveFailure.urlEncoding))
            return
        }
        
        self.apiCall(method: "DELETE", baseURL: graphBaseURL, path: encodedPath, additionalHeaders: basicHeaders(), expectedFailureBody: .data) { apiResult, statusCode, responseHeaders in
            
            guard statusCode == HTTPStatusCode.noContent else {
                guard let apiResult = apiResult else {
                    completion(.failure(OneDriveFailure.noAPIResult))
                    return
                }
                
                guard case .data(let data) = apiResult else {
                    completion(.failure(OneDriveFailure.noDataInAPIResult))
                    return
                }
                
                let decoder = JSONDecoder()
                guard let errorResult = try? decoder.decode(ErrorResult.self, from: data) else {
                    completion(.failure(OneDriveFailure.couldNotDecodeError))
                    return
                }
                
                guard !self.accessTokenIsRevokedOrExpired(errorResult: errorResult, statusCode: statusCode) else {
                    completion(.accessTokenRevokedOrExpired)
                    return
                }
                
                completion(.failure(OneDriveFailure.badStatusCode(statusCode, nil)))
                return
            }
            
            completion(.success(()))
        }
    }
    
    func deleteFile(cloudFileName: String, completion: @escaping (Result<()>) -> ()) {
        // Before we can delete the file, we need it's item id
        checkForFile(fileName: cloudFileName) {[weak self] result in
            guard let self = self else {
                completion(.failure(OneDriveFailure.couldNotGetSelf))
                return
            }
            
            switch result {
            case .success(.fileFound(let fileResult)):
                self.deleteFile(itemId: fileResult.id, completion: completion)
            case .success(.fileNotFound):
                completion(.failure(OneDriveFailure.fileNotFound))
            case .accessTokenRevokedOrExpired:
                completion(.accessTokenRevokedOrExpired)
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }
}

