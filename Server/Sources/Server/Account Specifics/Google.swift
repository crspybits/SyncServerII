//
//  Google.swift
//  Server
//
//  Created by Christopher Prince on 12/22/16.
//
//

import Foundation
import Credentials
import CredentialsGoogle
import PerfectLib
import KituraNet
import SwiftyJSON

class GoogleCreds : Creds {
    // The following keys are for storage into mySQL
    
    static let accessTokenKey = "accessToken"
    var accessToken: String!
    
    static let refreshTokenKey = "refreshToken"
    // This is obtained via the serverAuthCode
    var refreshToken: String?
    
    // Only present transiently.
    var serverAuthCode:String?
    
    override init() {
        super.init()
        self.accountType = .Google
    }
    
    override static func fromJSON(s:String) -> Creds? {
        guard let data = s.data(using: String.Encoding.utf8) else {
            return nil
        }
        
        var json:Any?
        
        do {
            try json = JSONSerialization.jsonObject(with: data, options: JSONSerialization.ReadingOptions(rawValue: UInt(0)))
        } catch (let error) {
            Log.error(message: "Error in JSON conversion: \(error)")
            return nil
        }
        
        guard let jsonDict = json as? [String:String] else {
            Log.error(message: "Could not convert json to json Dict")
            return nil
        }
        
        let result = GoogleCreds()
        
        if jsonDict[accessTokenKey] == nil {
            Log.error(message: "No \(accessTokenKey) present.")
            return nil
        }
        else {
            result.accessToken = jsonDict[accessTokenKey]
        }
        
        // Allowing the refresh token to be optional-- because when creating a user account, we don't have it from the client.
        result.refreshToken = jsonDict[refreshTokenKey]
        
        return result
    }
    
    private func dictionaryToJSONString(dict:[String:Any]) -> String? {
        var data:Data!
        
        do {
            try data = JSONSerialization.data(withJSONObject: dict, options: JSONSerialization.WritingOptions(rawValue: UInt(0)))
        } catch (let error) {
            Log.error(message: "Could not convert json to data: \(error)")
            return nil
        }
        
        return String(data: data, encoding: String.Encoding.utf8)
    }
    
    override func toJSON() -> String? {
        var jsonDict = [String:String]()
        jsonDict[GoogleCreds.accessTokenKey] = self.accessToken
        jsonDict[GoogleCreds.refreshTokenKey] = self.refreshToken
        return dictionaryToJSONString(dict: jsonDict)
    }
    
    override static func fromProfile(profile:UserProfile) -> Creds? {
        guard let googleSpecificCreds = profile.accountSpecificCreds as? GoogleSpecificCreds else {
            Log.error(message: "Account specific creds were not GoogleSpecificCreds")
            return nil
        }
        
        let creds = GoogleCreds()
        creds.accessToken = googleSpecificCreds.accessToken
        creds.serverAuthCode = googleSpecificCreds.serverAuthCode
        return creds
    }
    
    private static let googleAPIAccessTokenKey = "access_token"
    private static let googleAPIRefreshTokenKey = "refresh_token"
    
    // Does an HTTP call to the www.googleapis.com endpoint given with path, the HTTP method, and the given body parameters (if any).
    private func googleAPICall(method:String, path:String,
        additionalHeaders: [String:String]? = nil, urlParameters:String? = nil, body:String? = nil,
        completion:@escaping (_ result: JSON?, HTTPStatusCode?)->()) {
        
        var requestOptions: [ClientRequest.Options] = []
        requestOptions.append(.schema("https://"))
        requestOptions.append(.hostname("www.googleapis.com"))
        requestOptions.append(.method(method))
        
        if urlParameters == nil {
            requestOptions.append(.path(path))
        }
        else {
            let escapedURLParams = urlParameters!.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed)
            requestOptions.append(.path(path + "?" + escapedURLParams!))
        }
        
        var headers = [String:String]()
        //headers["Accept"] = "application/json; charset=UTF-8"
        headers["Accept"] = "*/*"
        
        if additionalHeaders != nil {
            for (key, value) in additionalHeaders! {
                headers[key] = value
            }
        }
        
        requestOptions.append(.headers(headers))
 
        let req = HTTP.request(requestOptions) { response in
            if let response = response {
                let statusCode = response.statusCode
                Log.debug(message: "HTTP status code: \(statusCode)")
                if statusCode != HTTPStatusCode.OK {
                    completion(nil, statusCode)
                    return
                }
                
                var body = Data()
                do {
                    try response.readAllData(into: &body)
                    let jsonBody = JSON(data: body)
                    completion(jsonBody, statusCode)
                    return
                } catch (let error) {
                    Log.error(message: "Failed to read Google response: \(error)")
                }
            }
            
            completion(nil, nil)
        }
        
        if body == nil {
            req.end()
        }
        else {
            req.end(body!)
        }
    }
    
    enum RefreshError : Swift.Error {
    case badStatusCode(HTTPStatusCode?)
    case couldNotObtainParameterFromJSON
    }
    // Use the refresh token to generate a new access token.
    // If error is nil when the completion handler is called, then the accessToken of this object has been refreshed. It hasn't yet been persistently stored on this server.
    func refresh(completion:@escaping (Swift.Error?)->()) {
        // See "Using a refresh token" at https://developers.google.com/identity/protocols/OAuth2WebServer

        let bodyParameters = "client_id=\(Constants.session.googleClientId)&client_secret=\(Constants.session.googleClientSecret)&refresh_token=\(self.refreshToken!)&grant_type=refresh_token"
        Log.debug(message: "bodyParameters: \(bodyParameters)")
        
        let additionalHeaders = ["Content-Type": "application/x-www-form-urlencoded"]
        
        self.googleAPICall(method: "POST", path: "/oauth2/v4/token", additionalHeaders:additionalHeaders, body: bodyParameters) { jsonResult, statusCode in
            guard statusCode == HTTPStatusCode.OK else {
                completion(RefreshError.badStatusCode(statusCode))
                return
            }
            
            if let accessToken =
                jsonResult?[GoogleCreds.googleAPIAccessTokenKey].string {
                self.accessToken = accessToken
                Log.debug(message: "Refreshed access token: \(accessToken)")
                completion(nil)
                return
            }
            
            completion(RefreshError.couldNotObtainParameterFromJSON)
        }
    }
    
    enum GenerateTokensError : Swift.Error {
    case badStatusCode(HTTPStatusCode?)
    case couldNotObtainParameterFromJSON
    }
    
    // Use the serverAuthCode to generate a refresh and access token if there is one. If no error occurs, success is returned with true or false depending on whether the generation occurred successfully.
    override func generateTokens(completion:@escaping (_ success:Bool?, Swift.Error?)->()) {
        if self.serverAuthCode == nil {
            Log.info(message: "No serverAuthCode from client.")
            completion(false, nil)
            return
        }

        let bodyParameters = "code=\(self.serverAuthCode!)&client_id=\(Constants.session.googleClientId)&client_secret=\(Constants.session.googleClientSecret)&redirect_uri=&grant_type=authorization_code"
        Log.debug(message: "bodyParameters: \(bodyParameters)")
        
        let additionalHeaders = ["Content-Type": "application/x-www-form-urlencoded"]

        self.googleAPICall(method: "POST", path: "/oauth2/v4/token", additionalHeaders:additionalHeaders, body: bodyParameters) { jsonResult, statusCode in
            guard statusCode == HTTPStatusCode.OK else {
                completion(nil, GenerateTokensError.badStatusCode(statusCode))
                return
            }
            
            if let accessToken = jsonResult?[GoogleCreds.googleAPIAccessTokenKey].string,
                let refreshToken = jsonResult?[GoogleCreds.googleAPIRefreshTokenKey].string {
                self.accessToken = accessToken
                self.refreshToken = refreshToken
                Log.debug(message: "Obtained tokens: accessToken: \(accessToken)\n refreshToken: \(refreshToken)")
                completion(true, nil)
                return
            }
            
            completion(nil, GenerateTokensError.couldNotObtainParameterFromJSON)
        }
    }
    
    override func merge(withNewerCreds newerCreds:Creds) {
        assert(newerCreds is GoogleCreds, "Wrong other type of creds!")
        let newerGoogleCreds = newerCreds as! GoogleCreds
        
        if newerGoogleCreds.refreshToken != nil {
            self.refreshToken = newerGoogleCreds.refreshToken
        }
        
        self.accessToken = newerGoogleCreds.accessToken
    }
    
    enum ListFilesError : Swift.Error {
    case badStatusCode(HTTPStatusCode?)
    }
    
    /* If this isn't working for you, try:
        curl -H "Authorization: Bearer YourAccessToken" https://www.googleapis.com/drive/v3/files
    at the command line.
    */
    func listFiles(query:String? = nil, completion:@escaping (_ fileListing:JSON?, Swift.Error?)->()) {
        let additionalHeaders = ["Authorization" : "Bearer \(self.accessToken!)"]
        
        var urlParameters:String?
        
        if query != nil {
            urlParameters = "q=" + query!
        }
        
        self.googleAPICall(method: "GET", path: "/drive/v3/files", additionalHeaders:additionalHeaders, urlParameters:urlParameters) { (json, statusCode) in
            var error:ListFilesError?
            if statusCode != HTTPStatusCode.OK {
                error = .badStatusCode(statusCode)
            }
            completion(json, error)
        }
    }
    
    private let folderMimeType = "application/vnd.google-apps.folder"
    
    enum SearchForFolderError : Swift.Error {
    case noIdInResultingJSON
    case moreThanOneFolderWithName
    case noJSONDictionaryResult
    }
    
    // Considers it an error for there to be more than one folder with the given name.
    func searchForFolder(folderName:String, completion:@escaping (_ folderId:String?, Swift.Error?)->()) {
    
        let query = "mimeType='\(folderMimeType)' and name='\(folderName)' and trashed=false"
        
        self.listFiles(query:query) { (json, error) in
            // For the response structure, see https://developers.google.com/drive/v3/reference/files/list
            
            var resultId:String?
            var resultError:Swift.Error? = error
            
            if error != nil || json == nil || json!.type != .dictionary {
                if error == nil {
                    resultError = SearchForFolderError.noJSONDictionaryResult
                }
            }
            else {
                switch json!["files"].count {
                case 0:
                    // resultError will be nil as will resultId.
                    break
                    
                case 1:
                    if let fileArray = json!["files"].array,
                        let fileDict = fileArray[0].dictionary,
                        let id = fileDict["id"]?.string {
                        resultId = id
                    }
                    else {
                        resultError = SearchForFolderError.noIdInResultingJSON
                    }
                
                default:
                    resultError = SearchForFolderError.moreThanOneFolderWithName
                }
            }
            
            completion(resultId, resultError)
        }
    }
    
    enum CreateFolderError : Swift.Error {
    case badStatusCode(HTTPStatusCode?)
    case couldNotConvertJSONToString
    case noJSONDictionaryResult
    case noIdInResultingJSON
    }
    
    // Create a folder-- assumes it doesn't yet exist. This won't fail if you use it more than once with the same folder name, you just get multiple instances of a folder with the same name.
    func createFolder(folderName:String,
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
    
        self.googleAPICall(method: "POST", path: "/drive/v3/files", additionalHeaders:additionalHeaders, body:jsonString) { (json, statusCode) in
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
    
    enum TrashFileError: Swift.Error {
    case couldNotConvertJSONToString
    }
    
    // I've been unable to get this to work. The PATCH request is less than a year old in Kitura. Wonder if it could be having problems...
#if false
    // Move a file or folder to the trash on Google Drive.
    func trashFile(fileId:String, completion:@escaping (Swift.Error?)->()) {
        /* I am having problems getting this endpoint to work. The following curl statement did the job:
        curl -H "Content-Type: application/json; charset=UTF-8" -H "Authorization: Bearer ya29.CjDNA5hr2sKmWeNq8HzStIje4aaqDuocgpteKS5NYTvGKRIxCZKAHyNFB7ky_s7eyC8" -X PATCH -d '{"trashed":"true"}' https://www.googleapis.com/drive/v3/files/0B3xI3Shw5ptROTA2M1dfby1OVEk
        */
            
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
        
        self.googleAPICall(method: "DELETE", path: "/drive/v3/files/\(fileId)", additionalHeaders:additionalHeaders) { (json, statusCode) in
            if statusCode == HTTPStatusCode.noContent {
                completion(nil)
            }
            else {
                completion(DeleteFileError.badStatusCode(statusCode))
            }
        }
    }

    // For relatively small files-- e.g., <= 5MB, where the entire upload can be retried if it fails.
    func uploadSmallFile() {
    }
}
