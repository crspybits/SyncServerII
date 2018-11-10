//
//  GoogleCreds.swift
//  Server
//
//  Created by Christopher Prince on 12/22/16.
//
//

import LoggerAPI
import KituraNet
import Foundation
import SyncServerShared

// TODO: *5* MD5 checksums can be obtained from Google Drive: http://stackoverflow.com/questions/23462168/google-drive-md5-checksum-for-files 
// At least for Google Drive this ought to enable us to deal with issues of users modifying files and messing us up. i.e., we should drop the byte count support we have and go with a checksum validation.

// TODO: *0* Need automatic refreshing of the access token-- this should make client side testing easier: There should be no need to create a new access token every hour.

// TODO: *5* It looks like if we give the user a reader-only role on a file, then they will not be able to modify it. Which will help in terms of users potentially modifying SyncServer files and messing things up. See https://developers.google.com/drive/v3/reference/permissions QUESTION: Will the user then be able to delete the file?

private let folderMimeType = "application/vnd.google-apps.folder"

extension GoogleCreds : CloudStorage {
    enum ListFilesError : Swift.Error {
    case badStatusCode(HTTPStatusCode?)
    case nilAPIResult
    case badJSONResult
    case expiredOrRevokedToken
    }
    
    private static let md5ChecksumKey = "md5Checksum"
    
    private func revokedOrExpiredToken(result: APICallResult?) -> Bool {
        if let result = result {
            switch result {
            case .dictionary(let dict):
                if dict["error"] as? String == self.tokenRevokedOrExpired {
                    return true
                }
            default:
                break
            }
        }

        return false
    }
    
    /* If this isn't working for you, try:
        curl -H "Authorization: Bearer YourAccessToken" https://www.googleapis.com/drive/v3/files
    at the command line.
    */
    
    /* For query parameter, see https://developers.google.com/drive/v3/web/search-parameters
    
        fieldsReturned parameter indicates the collection of fields to be returned in the, scoped over the entire response (not just the files resources). See https://developers.google.com/drive/v3/web/performance#partial
            E.g., "files/id,files/size"
        See also see http://stackoverflow.com/questions/35143283/google-drive-api-v3-migration
    */
    // Not marked private for testing purposes. Don't call this directly outside of this class otherwise.
    func listFiles(query:String? = nil, fieldsReturned:String? = nil, completion:@escaping (_ fileListing:[String: Any]?, Swift.Error?)->()) {
        
        var urlParameters = ""

        if fieldsReturned != nil {
            urlParameters = "fields=" + fieldsReturned!
        }
        
        if query != nil {
            if urlParameters.count != 0 {
                urlParameters += "&"
            }
            
            urlParameters += "q=" + query!
        }
        
        var urlParams:String? = urlParameters
        if urlParameters.count == 0 {
            urlParams = nil
        }
        
        self.apiCall(method: "GET", path: "/drive/v3/files", urlParameters:urlParams) {[unowned self] (apiResult, statusCode, responseHeaders) in
        
            if self.revokedOrExpiredToken(result: apiResult) {
                completion(nil, ListFilesError.expiredOrRevokedToken)
                return
            }
            
            var error:ListFilesError?
            if statusCode != HTTPStatusCode.OK {
                error = .badStatusCode(statusCode)
            }
            
            guard apiResult != nil else {
                completion(nil, ListFilesError.nilAPIResult)
                return
            }
            
            guard case .dictionary(let dictionary) = apiResult! else {
                completion(nil, ListFilesError.badJSONResult)
                return
            }
            
            completion(dictionary, error)
        }
    }
    
    enum SearchError : Swift.Error {
    case noIdInResultingJSON
    case moreThanOneItemWithName
    case noJSONDictionaryResult
    case expiredOrRevokedToken
    }
    
    enum SearchType {
    case folder
    
    // If parentFolderId is nil, the root folder is assumed.
    case file(mimeType:String, parentFolderId:String?)
    
    case any // folders or files
    }
    
    struct SearchResult {
        let itemId:String
        
        // Google specific result-- a partial files resource for the file.
        // Contains fields: size, and id
        let dictionary:[String: Any]
        
        // Non-nil for files.
        let checkSum: String?
    }
    
    // Considers it an error for there to be more than one item with the given name.
    // Not marked private for testing purposes. Don't call this directly outside of this class otherwise.
    func searchFor(_ searchType: SearchType, itemName:String,
        completion:@escaping (_ result:SearchResult?, Swift.Error?)->()) {
        
        var query:String = ""
        switch searchType {
        case .folder:
            query = "mimeType='\(folderMimeType)' and "
            
        case .file(mimeType: let mimeType, parentFolderId: let parentFolderId):
            query += "mimeType='\(mimeType)' and "
            
            // See https://developers.google.com/drive/v3/web/folder
            var folderId = "root"
            
            if parentFolderId != nil {
                folderId = parentFolderId!
            }
            
            query += "'\(folderId)' in parents and "
            
        case .any:
            break
        }
        
        query += "name='\(itemName)' and trashed=false"
        
        // The structure of this wasn't obvious to me-- it's scoped over the entire response object, not just within the files resource. See also http://stackoverflow.com/questions/38853938/google-drive-api-v3-invalid-field-selection
        // And see https://developers.google.com/drive/api/v3/performance#partial
        let fieldsReturned = "files/id,files/\(GoogleCreds.md5ChecksumKey)"
        
        self.listFiles(query:query, fieldsReturned:fieldsReturned) { (dictionary, error) in
            // For the response structure, see https://developers.google.com/drive/v3/reference/files/list
            
            var result:SearchResult?
            var resultError:Swift.Error? = error
            
            if error != nil || dictionary == nil {
                if error == nil {
                    resultError = SearchError.noJSONDictionaryResult
                }
                else {
                    switch error! {
                    case ListFilesError.expiredOrRevokedToken:
                        resultError = SearchError.expiredOrRevokedToken
                    default:
                        break
                    }
                }
            }
            else {
                if let filesArray = dictionary!["files"] as? [Any]  {
                    switch filesArray.count {
                    case 0:
                        // resultError will be nil as will result.
                        break
                        
                    case 1:
                        if let fileDict = filesArray[0] as? [String: Any],
                            let id = fileDict["id"] as? String {
                            
                            // See https://developers.google.com/drive/api/v3/reference/files
                            let checkSum = fileDict[GoogleCreds.md5ChecksumKey] as? String

                            result = SearchResult(itemId: id, dictionary: fileDict, checkSum: checkSum)
                        }
                        else {
                            resultError = SearchError.noIdInResultingJSON
                        }
                    
                    default:
                        resultError = SearchError.moreThanOneItemWithName
                    }
                }
            }
            
            completion(result, resultError)
        }
    }
    
    enum CreateFolderError : Swift.Error {
    case badStatusCode(HTTPStatusCode?)
    case couldNotConvertJSONToString
    case badJSONResult
    case noJSONDictionaryResult
    case noIdInResultingJSON
    case nilAPIResult
    case expiredOrRevokedToken
    }
    
    // Create a folder-- assumes it doesn't yet exist. This won't fail if you use it more than once with the same folder name, you just get multiple instances of a folder with the same name.
    // Not marked private for testing purposes. Don't call this directly outside of this class otherwise.
    func createFolder(rootFolderName folderName:String,
        completion:@escaping (_ folderId:String?, Swift.Error?)->()) {
        
        // It's not obvious from the docs, but you use the /drive/v3/files endpoint (metadata only) for creating folders. Also not clear from the docs, you need to give the Content-Type in the headers. See https://developers.google.com/drive/v3/web/manage-uploads

        let additionalHeaders = [
            "Content-Type": "application/json; charset=UTF-8"
        ]
    
        let bodyDict = [
            "name" : folderName,
            "mimeType" : "\(folderMimeType)"
        ]
        
        guard let jsonString = JSONExtras.toJSONString(dict: bodyDict) else {
            completion(nil, CreateFolderError.couldNotConvertJSONToString)
            return
        }
    
        self.apiCall(method: "POST", path: "/drive/v3/files", additionalHeaders:additionalHeaders, body: .string(jsonString)) { (apiResult, statusCode, responseHeaders) in
            var resultId:String?
            var resultError:Swift.Error?
            
            if self.revokedOrExpiredToken(result: apiResult) {
                completion(nil, CreateFolderError.expiredOrRevokedToken)
                return
            }
            
            guard apiResult != nil else {
                completion(nil, CreateFolderError.nilAPIResult)
                return
            }
            
            guard case .dictionary(let dictionary) = apiResult! else {
                completion(nil, CreateFolderError.badJSONResult)
                return
            }
            
            if statusCode != HTTPStatusCode.OK {
                resultError = CreateFolderError.badStatusCode(statusCode)
            }
            else {
                if let id = dictionary["id"] as? String {
                    resultId = id
                }
                else {
                    resultError = CreateFolderError.noIdInResultingJSON
                }
            }
            
            completion(resultId, resultError)
        }
    }
    
    // Creates a root level folder if it doesn't exist. Returns the folderId in the completion if no error.
    // Not marked private for testing purposes. Don't call this directly outside of this class otherwise.
    // CreateFolderError.expiredOrRevokedToken or SearchError.expiredOrRevokedToken for expiry.
    func createFolderIfDoesNotExist(rootFolderName folderName:String,
        completion:@escaping (_ folderId:String?, Swift.Error?)->()) {
        self.searchFor(.folder, itemName: folderName) { (result, error) in
            if error == nil {
                if result == nil {
                    // Folder doesn't exist.
                    self.createFolder(rootFolderName: folderName) { (folderId, error) in
                        completion(folderId, error)
                    }
                }
                else {
                    // Folder does exist.
                    completion(result!.itemId, nil)
                }
            }
            else {
                completion(nil, error)
            }
        }
    }
    
    enum TrashFileError: Swift.Error {
    case couldNotConvertJSONToString
    }
    
    /* I've been unable to get this to work. The HTTP PATCH request is less than a year old in Kitura. Wonder if it could be having problems... It doesn't give an error, it gives the file's resource just like when in fact it does work, ie., with curl below.
        The following curl statement *did* do the job:
        curl -H "Content-Type: application/json; charset=UTF-8" -H "Authorization: Bearer ya29.CjDNA5hr2sKmWeNq8HzStIje4aaqDuocgpteKS5NYTvGKRIxCZKAHyNFB7ky_s7eyC8" -X PATCH -d '{"trashed":"true"}' https://www.googleapis.com/drive/v3/files/0B3xI3Shw5ptROTA2M1dfby1OVEk
    */
#if false
    // Move a file or folder to the trash on Google Drive.
    func trashFile(fileId:String, completion:@escaping (Swift.Error?)->()) {
        let bodyDict = [
            "trashed": "true"
        ]
        
        guard let jsonString = dictionaryToJSONString(dict: bodyDict) else {
            completion(TrashFileError.couldNotConvertJSONToString)
            return
        }
        
        let additionalHeaders = [
            "Content-Type": "application/json; charset=UTF-8",
        ]
        
        self.googleAPICall(method: "PATCH", path: "/drive/v3/files/\(fileId)", additionalHeaders:additionalHeaders, body: jsonString) { (json, error) in
            if error != nil {
                Log.error("\(error)")
            }
            completion(error)
        }
    }
#endif

    enum DeleteFileError :Swift.Error {
    case badStatusCode(HTTPStatusCode?)
    case expiredOrRevokedToken
    }
    
    // Permanently delete a file or folder
    // Not marked private for testing purposes. Don't call this directly outside of this class otherwise.
    func deleteFile(fileId:String, completion:@escaping (Swift.Error?)->()) {
        // See https://developers.google.com/drive/v3/reference/files/delete
        
        let additionalHeaders = [
            "Content-Type": "application/json; charset=UTF-8",
        ]
        
        self.apiCall(method: "DELETE", path: "/drive/v3/files/\(fileId)", additionalHeaders:additionalHeaders) { (apiResult, statusCode, responseHeaders) in
        
            if self.revokedOrExpiredToken(result: apiResult) {
                completion(DeleteFileError.expiredOrRevokedToken)
                return
            }
            
            // The "noContent" correct result was not apparent from the docs-- figured this out by experimentation.
            if statusCode == HTTPStatusCode.noContent {
                completion(nil)
            }
            else {
                completion(DeleteFileError.badStatusCode(statusCode))
            }
        }
    }

    enum UploadError : Swift.Error {
    case badStatusCode(HTTPStatusCode?)
    case couldNotObtainCheckSum
    case noCloudFolderName
    case noOptions
    case missingCloudFolderNameOrMimeType
    case expiredOrRevokedToken
    }
    
    // TODO: *1* It would be good to put some retry logic in here. With a timed fallback as well. e.g., if an upload fails the first time around, retry after a period of time. OR, do this when I generalize this scheme to use other cloud storage services-- thus the retry logic could work across each scheme.
    // For relatively small files-- e.g., <= 5MB, where the entire upload can be retried if it fails.
    func uploadFile(cloudFileName:String, data:Data, options:CloudStorageFileNameOptions?,
        completion:@escaping (Result<String>)->()) {
        
        // See https://developers.google.com/drive/v3/web/manage-uploads

        guard let options = options else {
            completion(.failure(UploadError.noOptions))
            return
        }
        
        let mimeType = options.mimeType
        guard let cloudFolderName = options.cloudFolderName else {
            completion(.failure(UploadError.missingCloudFolderNameOrMimeType))
            return
        }
        
        self.createFolderIfDoesNotExist(rootFolderName: cloudFolderName) { (folderId, error) in
            if let error = error {
                switch error {
                case CreateFolderError.expiredOrRevokedToken,
                    SearchError.expiredOrRevokedToken:
                    completion(.accessTokenRevokedOrExpired)
                default:
                    completion(.failure(error))
                }

                return
            }
            
            let searchType = SearchType.file(mimeType: mimeType, parentFolderId: folderId)
            
            // I'm going to do this before I attempt the upload-- because I don't want to upload the same file twice. This results in google drive doing odd things with the file names. E.g., 5200B98F-8CD8-4248-B41E-4DA44087AC3C.950DBB91-B152-4D5C-B344-9BAFF49021B7 (1).0
            self.searchFor(searchType, itemName: cloudFileName) { (result, error) in
                if error == nil {
                    if result == nil {
                        self.completeSmallFileUpload(folderId: folderId!, searchType:searchType, cloudFileName: cloudFileName, data: data, mimeType: mimeType, completion: completion)
                    }
                    else {
                        completion(.failure(CloudStorageError.alreadyUploaded))
                    }
                }
                else {
                    switch error! {
                    case SearchError.expiredOrRevokedToken:
                        completion(.accessTokenRevokedOrExpired)
                    default:
                        Log.error("Error in searchFor: \(String(describing: error))")
                        completion(.failure(error!))
                    }
                }
            }
        }
    }
    
    // See https://developers.google.com/drive/api/v3/multipart-upload
    private func completeSmallFileUpload(folderId:String, searchType:SearchType, cloudFileName: String, data: Data, mimeType:String, completion:@escaping (Result<String>)->()) {
        
        let boundary = Foundation.UUID().uuidString

        let additionalHeaders = [
            "Content-Type" : "multipart/related; boundary=\(boundary)"
        ]
        
        var urlParameters = "uploadType=multipart"
        urlParameters += "&fields=" + GoogleCreds.md5ChecksumKey
        
        let firstPart =
            "--\(boundary)\r\n" +
            "Content-Type: application/json; charset=UTF-8\r\n" +
            "\r\n" +
            "{\r\n" +
                "\"name\": \"\(cloudFileName)\",\r\n" +
                "\"parents\": [\r\n" +
                    "\"\(folderId)\"\r\n" +
                "]\r\n" +
            "}\r\n" +
            "\r\n" +
            "--\(boundary)\r\n" +
            "Content-Type: \(mimeType)\r\n" +
            "\r\n"
        
        var multiPartData = firstPart.data(using: .utf8)!
        multiPartData.append(data)
        
        let endBoundary = "\r\n--\(boundary)--".data(using: .utf8)!
        multiPartData.append(endBoundary)

        self.apiCall(method: "POST", path: "/upload/drive/v3/files", additionalHeaders:additionalHeaders, urlParameters:urlParameters, body: .data(multiPartData)) { (json, statusCode, responseHeaders) in
        
            if self.revokedOrExpiredToken(result: json) {
                completion(.accessTokenRevokedOrExpired)
                return
            }

            if statusCode == HTTPStatusCode.OK {
                guard let json = json,
                    case .dictionary(let dict) = json,
                    let checkSum = dict[GoogleCreds.md5ChecksumKey] as? String else {
                    completion(.failure(UploadError.couldNotObtainCheckSum))
                    return
                }
                
                completion(.success(checkSum))
            }
            else {
                // Error case
                Log.error("Error in completeSmallFileUpload: statusCode=\(String(describing: statusCode))")
                completion(.failure(UploadError.badStatusCode(statusCode)))
            }
        }
    }
    
    enum SearchForFileError : Swift.Error {
        case cloudFolderDoesNotExist
        case cloudFileDoesNotExist(cloudFileName:String)
        case expiredOrRevokedToken
    }
    
    enum LookupFileError: Swift.Error {
        case noOptions
        case noCloudFolderName
    }
    
    func lookupFile(cloudFileName:String, options:CloudStorageFileNameOptions?,
        completion:@escaping (Result<Bool>)->()) {
        
        guard let options = options else {
            completion(.failure(LookupFileError.noOptions))
            return
        }
        
        guard let cloudFolderName = options.cloudFolderName else {
            completion(.failure(LookupFileError.noCloudFolderName))
            return
        }
        
        searchFor(cloudFileName: cloudFileName, inCloudFolder: cloudFolderName, fileMimeType: options.mimeType) { (cloudFileId, checkSum, error) in

            switch error {
            case .none:
                completion(.success(true))
                
            case .some(SearchForFileError.cloudFileDoesNotExist):
                completion(.success(false))
                
            case .some(SearchForFileError.expiredOrRevokedToken):
                completion(.accessTokenRevokedOrExpired)
                
            default:
                 completion(.failure(error!))
            }
        }
    }
    
    func searchFor(cloudFileName:String, inCloudFolder cloudFolderName:String, fileMimeType mimeType:String, completion:@escaping (_ cloudFileId: String?, _ checkSum: String?, Swift.Error?) -> ()) {
        
        self.searchFor(.folder, itemName: cloudFolderName) { (result, error) in
            if let error = error {
                switch error {
                case SearchError.expiredOrRevokedToken:
                    completion(nil, nil, SearchForFileError.expiredOrRevokedToken)
                    return
                default:
                    break
                }
            }
            
            if result == nil {
                // Folder doesn't exist. Yikes!
                completion(nil, nil, SearchForFileError.cloudFolderDoesNotExist)
            }
            else {
                // Folder exists. Next need to find the id of our file within this folder.
                
                let searchType = SearchType.file(mimeType: mimeType, parentFolderId: result!.itemId)
                self.searchFor(searchType, itemName: cloudFileName) { (result, error) in
                    if let error = error {
                        switch error {
                        case SearchError.expiredOrRevokedToken:
                            completion(nil, nil, SearchForFileError.expiredOrRevokedToken)
                        default:
                            break
                        }
                    }
                    
                    if result == nil {
                        completion(nil, nil, SearchForFileError.cloudFileDoesNotExist(cloudFileName: cloudFileName))
                    }
                    else {
                        completion(result!.itemId, result!.checkSum, nil)
                    }
                }
            }
        }
    }
    
    enum DownloadSmallFileError : Swift.Error {
        case badStatusCode(HTTPStatusCode?)
        case nilAPIResult
        case noDataInAPIResult
        case noOptions
        case noCloudFolderName
        case fileNotFound
        case expiredOrRevokedToken
    }
    
    func downloadFile(cloudFileName:String, options:CloudStorageFileNameOptions?, completion:@escaping (DownloadResult)->()) {
        
        guard let options = options else {
            completion(.failure(DownloadSmallFileError.noOptions))
            return
        }
        
        guard let cloudFolderName = options.cloudFolderName else {
            completion(.failure(DownloadSmallFileError.noCloudFolderName))
            return
        }
        
        searchFor(cloudFileName: cloudFileName, inCloudFolder: cloudFolderName, fileMimeType: options.mimeType) { (cloudFileId, checkSum, error) in

            if error == nil {
                // File was found! Need to download it now.
                self.completeSmallFileDownload(fileId: cloudFileId!) { (data, error) in
                    if error == nil {
                        let downloadResult:DownloadResult = .success(data: data!, checkSum: checkSum!)
                        completion(downloadResult)
                    }
                    else {
                        switch error! {
                        case DownloadSmallFileError.fileNotFound:
                            completion(.fileNotFound)
                        case DownloadSmallFileError.expiredOrRevokedToken:
                            completion(.accessTokenRevokedOrExpired)
                        default:
                            completion(.failure(error!))
                        }
                    }
                }
            }
            else {
                switch error! {
                case SearchForFileError.cloudFileDoesNotExist:
                    completion(.fileNotFound)
                case SearchForFileError.expiredOrRevokedToken:
                    completion(.accessTokenRevokedOrExpired)
                default:
                    completion(.failure(error!))
                }
            }
        }
    }

    // Not `private` because of some testing.
    func completeSmallFileDownload(fileId:String, completion:@escaping (_ data:Data?, Swift.Error?)->()) {
        // See https://developers.google.com/drive/v3/web/manage-downloads
        /*
        GET https://www.googleapis.com/drive/v3/files/0B9jNhSvVjoIVM3dKcGRKRmVIOVU?alt=media
        Authorization: Bearer <ACCESS_TOKEN>
        */
        
        let path = "/drive/v3/files/\(fileId)?alt=media"
        
        self.apiCall(method: "GET", path: path, expectedSuccessBody: .data, expectedFailureBody: .json) { (apiResult, statusCode, responseHeaders) in
            
            if self.revokedOrExpiredToken(result: apiResult) {
                completion(nil, DownloadSmallFileError.expiredOrRevokedToken)
                return
            }
            
            /* When the fileId doesn't exist, apiResult from body as JSON is:
            apiResult: Optional(Server.APICallResult.dictionary(
                ["error":
                    ["code": 404,
                    "errors": [
                        ["locationType": "parameter",
                            "reason": "notFound",
                            "location": "fileId",
                            "message": "File not found: foobar.",
                            "domain": "global"
                        ]
                    ],
                    "message": "File not found: foobar."]
                ]))
            */
            
            if statusCode == HTTPStatusCode.notFound,
                case .dictionary(let dict)? = apiResult,
                let error = dict["error"] as? [String: Any],
                let errors = error["errors"] as? [[String: Any]],
                errors.count == 1,
                let reason = errors[0]["reason"] as? String,
                reason == "notFound" {
                
                completion(nil, DownloadSmallFileError.fileNotFound)
                return
            }
            
            if statusCode != HTTPStatusCode.OK {
                completion(nil, DownloadSmallFileError.badStatusCode(statusCode))
                return
            }
            
            guard apiResult != nil else {
                completion(nil, DownloadSmallFileError.nilAPIResult)
                return
            }
            
            guard case .data(let data) = apiResult! else {
                completion(nil, DownloadSmallFileError.noDataInAPIResult)
                return
            }
            
            completion(data, nil)
        }
    }
    
    enum DeletionError : Swift.Error {
        case noOptions
        case noCloudFolderName
    }
    
    func deleteFile(cloudFileName:String, options:CloudStorageFileNameOptions?,
        completion:@escaping (Result<()>)->()) {
        
        guard let options = options else {
            completion(.failure(DeletionError.noOptions))
            return
        }
        
        guard let cloudFolderName = options.cloudFolderName else {
            completion(.failure(DeletionError.noCloudFolderName))
            return
        }
        
        searchFor(cloudFileName: cloudFileName, inCloudFolder: cloudFolderName, fileMimeType: options.mimeType) { (cloudFileId, checkSum, error) in
            if error == nil {
                // File was found! Need to delete it now.
                self.deleteFile(fileId: cloudFileId!) { error in
                    if error == nil {
                        completion(.success(()))
                    }
                    else {
                        switch error! {
                        case DeleteFileError.expiredOrRevokedToken:
                            completion(.accessTokenRevokedOrExpired)
                        default:
                            completion(.failure(error!))
                        }
                    }
                }
            }
            else {
                switch error! {
                case SearchForFileError.expiredOrRevokedToken:
                    completion(.accessTokenRevokedOrExpired)
                default:
                    completion(.failure(error!))
                }
            }
        }
    }
}
