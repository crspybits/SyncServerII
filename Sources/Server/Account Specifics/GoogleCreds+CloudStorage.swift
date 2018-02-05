//
//  GoogleCreds.swift
//  Server
//
//  Created by Christopher Prince on 12/22/16.
//
//

import LoggerAPI
import KituraNet
import SwiftyJSON
import Foundation
import SyncServerShared
import PerfectLib

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
    func listFiles(query:String? = nil, fieldsReturned:String? = nil, completion:@escaping (_ fileListing:JSON?, Swift.Error?)->()) {
        
        var urlParameters = ""

        if fieldsReturned != nil {
            urlParameters = "fields=" + fieldsReturned!
        }
        
        if query != nil {
            if urlParameters.characters.count != 0 {
                urlParameters += "&"
            }
            
            urlParameters += "q=" + query!
        }
        
        var urlParams:String? = urlParameters
        if urlParameters.characters.count == 0 {
            urlParams = nil
        }
        
        self.apiCall(method: "GET", path: "/drive/v3/files", urlParameters:urlParams) { (apiResult, statusCode) in
            
            var error:ListFilesError?
            if statusCode != HTTPStatusCode.OK {
                error = .badStatusCode(statusCode)
            }
            
            guard apiResult != nil else {
                completion(nil, ListFilesError.nilAPIResult)
                return
            }
            
            guard case .json(let jsonResult) = apiResult! else {
                completion(nil, ListFilesError.badJSONResult)
                return
            }
            
            completion(jsonResult, error)
        }
    }
    
    enum SearchError : Swift.Error {
    case noIdInResultingJSON
    case moreThanOneItemWithName
    case noJSONDictionaryResult
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
        let json:[String: JSON]
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
        let fieldsReturned = "files/id,files/size"
        
        self.listFiles(query:query, fieldsReturned:fieldsReturned) { (json, error) in
            // For the response structure, see https://developers.google.com/drive/v3/reference/files/list
            
            var result:SearchResult?
            var resultError:Swift.Error? = error
            
            if error != nil || json == nil || json!.type != .dictionary {
                if error == nil {
                    resultError = SearchError.noJSONDictionaryResult
                }
            }
            else {
                switch json!["files"].count {
                case 0:
                    // resultError will be nil as will result.
                    break
                    
                case 1:
                    if let fileArray = json!["files"].array,
                        let fileDict = fileArray[0].dictionary,
                        let id = fileDict["id"]?.string {
                        result = SearchResult(itemId: id, json: fileDict)
                    }
                    else {
                        resultError = SearchError.noIdInResultingJSON
                    }
                
                default:
                    resultError = SearchError.moreThanOneItemWithName
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
    
        self.apiCall(method: "POST", path: "/drive/v3/files", additionalHeaders:additionalHeaders, body: .string(jsonString)) { (apiResult, statusCode) in
            var resultId:String?
            var resultError:Swift.Error?
            
            guard apiResult != nil else {
                completion(nil, CreateFolderError.nilAPIResult)
                return
            }
            
            guard case .json(let jsonResult) = apiResult! else {
                completion(nil, CreateFolderError.badJSONResult)
                return
            }
            
            if statusCode != HTTPStatusCode.OK {
                resultError = CreateFolderError.badStatusCode(statusCode)
            }
            else if jsonResult.type != .dictionary {
                resultError = CreateFolderError.noJSONDictionaryResult
            }
            else {
                if let id = jsonResult["id"].string {
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
    }
    
    // Permanently delete a file or folder
    // Not marked private for testing purposes. Don't call this directly outside of this class otherwise.
    func deleteFile(fileId:String, completion:@escaping (Swift.Error?)->()) {
        // See https://developers.google.com/drive/v3/reference/files/delete
        
        let additionalHeaders = [
            "Content-Type": "application/json; charset=UTF-8",
        ]
        
        self.apiCall(method: "DELETE", path: "/drive/v3/files/\(fileId)", additionalHeaders:additionalHeaders) { (json, statusCode) in
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
    case couldNotObtainFileSize
    case fileAlreadyExists
    case noCloudFolderName
    case noOptions
    }
    
    // TODO: *1* It would be good to put some retry logic in here. With a timed fallback as well. e.g., if an upload fails the first time around, retry after a period of time. OR, do this when I generalize this scheme to use other cloud storage services-- thus the retry logic could work across each scheme.
    // For relatively small files-- e.g., <= 5MB, where the entire upload can be retried if it fails.
    func uploadFile(cloudFileName:String, data:Data, options:CloudStorageFileNameOptions?,
        completion:@escaping (Result<Int>)->()) {
        
        // See https://developers.google.com/drive/v3/web/manage-uploads

        guard let options = options else {
            completion(.failure(UploadError.noOptions))
            return
        }
        
        self.createFolderIfDoesNotExist(rootFolderName: options.cloudFolderName) { (folderId, error) in
            if error != nil {
                completion(.failure(error!))
                return
            }
            
            let searchType = SearchType.file(mimeType: options.mimeType, parentFolderId: folderId)
            
            // I'm going to do this before I attempt the upload-- because I don't want to upload the same file twice. This results in google drive doing odd things with the file names. E.g., 5200B98F-8CD8-4248-B41E-4DA44087AC3C.950DBB91-B152-4D5C-B344-9BAFF49021B7 (1).0
            self.searchFor(searchType, itemName: cloudFileName) { (result, error) in
                if error == nil {
                    if result == nil {
                        self.completeSmallFileUpload(folderId: folderId!, searchType:searchType, cloudFileName: cloudFileName, data: data, mimeType: options.mimeType, completion: completion)
                    }
                    else {
                        completion(.failure(UploadError.fileAlreadyExists))
                    }
                }
                else {
                    Log.error("Error in searchFor: \(String(describing: error))")
                    completion(.failure(error!))
                }
            }
        }
    }
    
    private func completeSmallFileUpload(folderId:String, searchType:SearchType, cloudFileName: String, data: Data, mimeType:String, completion:@escaping (Result<Int>)->()) {
        
        let boundary = PerfectLib.UUID().string

        let additionalHeaders = [
            "Content-Type" : "multipart/related; boundary=\(boundary)"
        ]
        
        let urlParameters = "uploadType=multipart"
        
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

        self.apiCall(method: "POST", path: "/upload/drive/v3/files", additionalHeaders:additionalHeaders, urlParameters:urlParameters, body: .data(multiPartData)) { (json, statusCode) in

            if statusCode != HTTPStatusCode.OK {
                // Error case
                Log.error("Error in completeSmallFileUpload: statusCode=\(String(describing: statusCode))")
                completion(.failure(UploadError.badStatusCode(statusCode)))
            }
            else {
                // Success case
                // TODO: *4* This probably doesn't have to do another Google Drive API call, rather it can just put the fields parameter on the call to upload the file-- and we'll get back the size.

                self.searchFor(searchType, itemName: cloudFileName) { (result, error) in
                    if error == nil {
                        if let sizeString = result?.json["size"]?.string,
                            let size = Int(sizeString) {
                            completion(.success(size))
                        }
                        else {
                            completion(.failure(UploadError.couldNotObtainFileSize))
                        }
                    }
                    else {
                        Log.error("Error in completeSmallFileUpload.searchFor: statusCode=\(String(describing: error))")
                        completion(.failure(error!))
                    }
                }
            }
        }
    }
    
    enum SearchForFileError : Swift.Error {
    case cloudFolderDoesNotExist
    case cloudFileDoesNotExist(cloudFileName:String)
    }
    
    enum LookupFileError: Swift.Error {
    case noOptions
    }
    
    func lookupFile(cloudFileName:String, options:CloudStorageFileNameOptions?,
        completion:@escaping (Result<Bool>)->()) {
        
        guard let options = options else {
            completion(.failure(LookupFileError.noOptions))
            return
        }
        
        searchFor(cloudFileName: cloudFileName, inCloudFolder: options.cloudFolderName, fileMimeType: options.mimeType) { (cloudFileId, error) in

            switch error {
            case .none:
                completion(.success(true))
                
            case .some(SearchForFileError.cloudFileDoesNotExist):
                 completion(.success(false))
                
            default:
                 completion(.failure(error!))
            }
        }
    }
    
    func searchFor(cloudFileName:String, inCloudFolder cloudFolderName:String, fileMimeType mimeType:String, completion:@escaping (_ cloudFileId: String?, Swift.Error?) -> ()) {
        
        self.searchFor(.folder, itemName: cloudFolderName) { (result, error) in
            if result == nil {
                // Folder doesn't exist. Yikes!
                completion(nil, SearchForFileError.cloudFolderDoesNotExist)
            }
            else {
                // Folder exists. Next need to find the id of our file within this folder.
                
                let searchType = SearchType.file(mimeType: mimeType, parentFolderId: result!.itemId)
                self.searchFor(searchType, itemName: cloudFileName) { (result, error) in
                    if result == nil {
                        completion(nil, SearchForFileError.cloudFileDoesNotExist(cloudFileName: cloudFileName))
                    }
                    else {
                        completion(result!.itemId, nil)
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
    }

    func downloadFile(cloudFileName:String, options:CloudStorageFileNameOptions?, completion:@escaping (Result<Data>)->()) {
        
        guard let options = options else {
            completion(.failure(DownloadSmallFileError.noOptions))
            return
        }
        
        searchFor(cloudFileName: cloudFileName, inCloudFolder: options.cloudFolderName, fileMimeType: options.mimeType) { (cloudFileId, error) in
            if error == nil {
                // File was found! Need to download it now.
                self.completeSmallFileDownload(fileId: cloudFileId!) { (data, error) in
                    if error == nil {
                        completion(.success(data!))
                    }
                    else {
                        completion(.failure(error!))
                    }
                }
            }
            else {
                completion(.failure(error!))
            }
        }
    }
    
    private func completeSmallFileDownload(fileId:String, completion:@escaping (_ data:Data?, Swift.Error?)->()) {
        // See https://developers.google.com/drive/v3/web/manage-downloads
        /*
        GET https://www.googleapis.com/drive/v3/files/0B9jNhSvVjoIVM3dKcGRKRmVIOVU?alt=media
        Authorization: Bearer <ACCESS_TOKEN>
        */
        
        let path = "/drive/v3/files/\(fileId)?alt=media"
        
        self.apiCall(method: "GET", path: path, expectingData: true) { (apiResult, statusCode) in
        
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
    }
    
    func deleteFile(cloudFileName:String, options:CloudStorageFileNameOptions?,
        completion:@escaping (Swift.Error?)->()) {
        
        guard let options = options else {
            completion(DeletionError.noOptions)
            return
        }
        
        searchFor(cloudFileName: cloudFileName, inCloudFolder: options.cloudFolderName, fileMimeType: options.mimeType) { (cloudFileId, error) in
            if error == nil {
                // File was found! Need to delete it now.
                self.deleteFile(fileId: cloudFileId!) { error in
                    if error == nil {
                        completion(nil)
                    }
                    else {
                        completion(error)
                    }
                }
            }
            else {
                completion(error)
            }
        }
    }
}
