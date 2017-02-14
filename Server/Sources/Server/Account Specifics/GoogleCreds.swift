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

// Credentials basis for making Google endpoint calls.

class GoogleCreds : Creds {
    // The following keys are for conversion <-> JSON (e.g., to store this into a database).
    
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
        self.baseURL = "www.googleapis.com"
    }
    
    override static func fromJSON(s:String) -> Creds? {
        guard let jsonDict = s.toJSONDictionary() as? [String:String] else {
            Log.error(message: "Could not convert string to JSON [String:String]: \(s)")
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
    
    func dictionaryToJSONString(dict:[String:Any]) -> String? {
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
    
    static let googleAPIAccessTokenKey = "access_token"
    static let googleAPIRefreshTokenKey = "refresh_token"
    
    enum GenerateTokensError : Swift.Error {
    case badStatusCode(HTTPStatusCode?)
    case couldNotObtainParameterFromJSON
    case nilAPIResult
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

        self.apiCall(method: "POST", path: "/oauth2/v4/token", additionalHeaders:additionalHeaders, body: .string(bodyParameters)) { apiResult, statusCode in
            guard statusCode == HTTPStatusCode.OK else {
                completion(nil, GenerateTokensError.badStatusCode(statusCode))
                return
            }
            
            guard apiResult != nil else {
                completion(nil, GenerateTokensError.nilAPIResult)
                return
            }
            
            if case .json(let jsonResult) = apiResult!,
                let accessToken = jsonResult[GoogleCreds.googleAPIAccessTokenKey].string,
                let refreshToken = jsonResult[GoogleCreds.googleAPIRefreshTokenKey].string {
                
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
    
    enum RefreshError : Swift.Error {
    case badStatusCode(HTTPStatusCode?)
    case couldNotObtainParameterFromJSON
    case nilAPIResult
    case badJSONResult
    }
    
    // Use the refresh token to generate a new access token.
    // If error is nil when the completion handler is called, then the accessToken of this object has been refreshed. It hasn't yet been persistently stored on this server.
    func refresh(completion:@escaping (Swift.Error?)->()) {
        // See "Using a refresh token" at https://developers.google.com/identity/protocols/OAuth2WebServer

        let bodyParameters = "client_id=\(Constants.session.googleClientId)&client_secret=\(Constants.session.googleClientSecret)&refresh_token=\(self.refreshToken!)&grant_type=refresh_token"
        Log.debug(message: "bodyParameters: \(bodyParameters)")
        
        let additionalHeaders = ["Content-Type": "application/x-www-form-urlencoded"]
        
        self.apiCall(method: "POST", path: "/oauth2/v4/token", additionalHeaders:additionalHeaders, body: .string(bodyParameters)) { apiResult, statusCode in
            guard statusCode == HTTPStatusCode.OK else {
                completion(RefreshError.badStatusCode(statusCode))
                return
            }
            
            guard apiResult != nil else {
                completion(RefreshError.nilAPIResult)
                return
            }
            
            guard case .json(let jsonResult) = apiResult! else {
                completion(RefreshError.badJSONResult)
                return
            }
            
            if let accessToken =
                jsonResult[GoogleCreds.googleAPIAccessTokenKey].string {
                self.accessToken = accessToken
                Log.debug(message: "Refreshed access token: \(accessToken)")
                completion(nil)
                return
            }
            
            completion(RefreshError.couldNotObtainParameterFromJSON)
        }
    }
}
