//
//  Google.swift
//  Server
//
//  Created by Christopher Prince on 12/22/16.
//
//

import PerfectLib
import KituraNet
import SwiftyJSON
import Foundation

private let folderMimeType = "application/vnd.google-apps.folder"

extension GoogleCreds {    
    enum ListFilesError : Swift.Error {
    case badStatusCode(HTTPStatusCode?)
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
    func listFiles(query:String? = nil, fieldsReturned:String? = nil, completion:@escaping (_ fileListing:JSON?, Swift.Error?)->()) {
        let additionalHeaders = ["Authorization" : "Bearer \(self.accessToken!)"]
        
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
        
        self.apiCall(method: "GET", path: "/drive/v3/files", additionalHeaders:additionalHeaders, urlParameters:urlParams) { (json, statusCode) in
            var error:ListFilesError?
            if statusCode != HTTPStatusCode.OK {
                error = .badStatusCode(statusCode)
            }
            completion(json, error)
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
    func searchFor(_ searchType: SearchType, itemName:String, completion:@escaping (_ result:SearchResult?, Swift.Error?)->()) {
        
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
    case noJSONDictionaryResult
    case noIdInResultingJSON
    }
    
    // Create a folder-- assumes it doesn't yet exist. This won't fail if you use it more than once with the same folder name, you just get multiple instances of a folder with the same name.
    func createFolder(rootFolderName folderName:String,
        completion:@escaping (_ folderId:String?, Swift.Error?)->()) {
        
        // It's not obvious from the docs, but you use the /drive/v3/files endpoint (metadata only) for creating folders. Also not clear from the docs, you need to give the Content-Type in the headers. See https://developers.google.com/drive/v3/web/manage-uploads

        let additionalHeaders = [
            "Authorization" : "Bearer \(self.accessToken!)",
            "Content-Type": "application/json; charset=UTF-8"
        ]
    
        let bodyDict = [
            "name" : folderName,
            "mimeType" : "\(folderMimeType)"
        ]
        
        guard let jsonString = dictionaryToJSONString(dict: bodyDict) else {
            completion(nil, CreateFolderError.couldNotConvertJSONToString)
            return
        }
    
        self.apiCall(method: "POST", path: "/drive/v3/files", additionalHeaders:additionalHeaders, body: .string(jsonString)) { (json, statusCode) in
            var resultId:String?
            var resultError:Swift.Error?
            
            if statusCode != HTTPStatusCode.OK {
                resultError = CreateFolderError.badStatusCode(statusCode)
            }
            else if json == nil || json!.type != .dictionary {
                resultError = CreateFolderError.noJSONDictionaryResult
            }
            else {
                if let id = json!["id"].string {
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
            "Authorization" : "Bearer \(self.accessToken!)"
        ]
        
        self.googleAPICall(method: "PATCH", path: "/drive/v3/files/\(fileId)", additionalHeaders:additionalHeaders, body: jsonString) { (json, error) in
            if error != nil {
                Log.error(message: "\(error)")
            }
            completion(error)
        }
    }
#endif

    enum DeleteFileError :Swift.Error {
    case badStatusCode(HTTPStatusCode?)
    }
    
    // Permanently delete a file or folder
    func deleteFile(fileId:String, completion:@escaping (Swift.Error?)->()) {
        // See https://developers.google.com/drive/v3/reference/files/delete
        
        let additionalHeaders = [
            "Content-Type": "application/json; charset=UTF-8",
            "Authorization" : "Bearer \(self.accessToken!)"
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
    }
    
    // For relatively small files-- e.g., <= 5MB, where the entire upload can be retried if it fails.
    func uploadSmallFile(request:UploadFileRequest,
        completion:@escaping (_ fileSizeOnServerInBytes:Int?, Swift.Error?)->()) {
        
        // See https://developers.google.com/drive/v3/web/manage-uploads
        
        self.createFolderIfDoesNotExist(rootFolderName: request.cloudFolderName) { (folderId, error) in
            if error != nil {
                completion(nil, error)
                return
            }
            
            let boundary = PerfectLib.UUID().string

            let additionalHeaders = [
                "Authorization" : "Bearer \(self.accessToken!)",
                "Content-Type" : "multipart/related; boundary=\(boundary)"
            ]
            
            let urlParameters = "uploadType=multipart"
            
            let firstPart =
                "--\(boundary)\r\n" +
                "Content-Type: application/json; charset=UTF-8\r\n" +
                "\r\n" +
                "{\r\n" +
                    "\"name\": \"\(request.cloudFileName())\",\r\n" +
                    "\"parents\": [\r\n" +
                        "\"\(folderId!)\"\r\n" +
                    "]\r\n" +
                "}\r\n" +
                "\r\n" +
                "--\(boundary)\r\n" +
                "Content-Type: \(request.mimeType!)\r\n" +
                "\r\n"
            
            var multiPartData = firstPart.data(using: .utf8)!
            multiPartData.append(request.data)
            
            let endBoundary = "\r\n--\(boundary)--".data(using: .utf8)!
            multiPartData.append(endBoundary)

            self.apiCall(method: "POST", path: "/upload/drive/v3/files", additionalHeaders:additionalHeaders, urlParameters:urlParameters, body: .data(multiPartData)) { (json, statusCode) in
                var resultError:Swift.Error?

                if statusCode != HTTPStatusCode.OK {
                    resultError = UploadError.badStatusCode(statusCode)
                    completion(nil, resultError)
                }
                else {
                    let searchType = SearchType.file(mimeType: request.mimeType, parentFolderId: folderId)
                    self.searchFor(searchType, itemName: request.cloudFileName()) { (result, error) in
                        if error == nil {
                            if let sizeString = result?.json["size"]?.string,
                                let size = Int(sizeString) {
                                completion(size, resultError)
                            }
                            else {
                                completion(nil, UploadError.couldNotObtainFileSize)
                            }
                        }
                        else {
                            completion(nil, error)
                        }
                    }
                }
            }
        }
    }
}
