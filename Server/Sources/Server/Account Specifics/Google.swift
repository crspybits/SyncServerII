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
    
    override func toJSON() -> String? {
        var jsonDict = [String:String]()
        jsonDict[GoogleCreds.accessTokenKey] = self.accessToken
        jsonDict[GoogleCreds.refreshTokenKey] = self.refreshToken
        
        var data:Data!
        
        do {
            try data = JSONSerialization.data(withJSONObject: jsonDict, options: JSONSerialization.WritingOptions(rawValue: UInt(0)))
        } catch (let error) {
            Log.error(message: "Could not convert json to data: \(error)")
            return nil
        }
        
        return String(data: data, encoding: String.Encoding.utf8)
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
    
    enum RefreshError : Swift.Error {
        case error(String)
    }
    
    private static let googleAPIAccessTokenKey = "access_token"
    private static let googleAPIRefreshTokenKey = "refresh_token"
    
    // Does a POST HTTP call to the www.googleapis.com /oauth2/v4/token endoint with the given body parameters.
    private func googleAPICall(bodyParameters:String,
        completion:@escaping (_ result: JSON?, Swift.Error?)->()) {
        
        var requestOptions: [ClientRequest.Options] = []
        requestOptions.append(.schema("https://"))
        requestOptions.append(.hostname("www.googleapis.com"))
        requestOptions.append(.method("POST"))
        requestOptions.append(.path("/oauth2/v4/token"))
        
        var headers = [String:String]()
        headers["Accept"] = "application/json"
        headers["Content-Type"] = "application/x-www-form-urlencoded"
        requestOptions.append(.headers(headers))
 
        let req = HTTP.request(requestOptions) { response in
            if let response = response {
                let statusCode = response.statusCode
                Log.debug(message: "HTTP status code: \(statusCode)")
                if statusCode != HTTPStatusCode.OK {
                    completion(nil, RefreshError.error("Bad status code: \(statusCode)"))
                    return
                }
                
                var body = Data()
                do {
                    try response.readAllData(into: &body)
                    let jsonBody = JSON(data: body)
                    completion(jsonBody, nil)
                    return
                } catch (let error) {
                    Log.error(message: "Failed to read Google response: \(error)")
                }
            }
            
            completion(nil, RefreshError.error("Failed on googleAPICall"))
        }
        
        req.end(bodyParameters)
    }
    
    // Use the refresh token to generate a new access token.
    // If error is nil when the completion handler is called, then the accessToken of this object has been refreshed. It hasn't yet been persistently stored on this server.
    func refresh(completion:@escaping (Swift.Error?)->()) {
        // See "Using a refresh token" at https://developers.google.com/identity/protocols/OAuth2WebServer

        let bodyParameters = "client_id=\(Constants.session.googleClientId)&client_secret=\(Constants.session.googleClientSecret)&refresh_token=\(self.refreshToken!)&grant_type=refresh_token"
        Log.debug(message: "bodyParameters: \(bodyParameters)")
        
        self.googleAPICall(bodyParameters: bodyParameters) { jsonResult, error in
            guard error == nil else {
                completion(error)
                return
            }
            
            if let accessToken =
                jsonResult?[GoogleCreds.googleAPIAccessTokenKey].string {
                self.accessToken = accessToken
                Log.debug(message: "Refreshed access token: \(accessToken)")
                completion(nil)
                return
            }
            
            completion(RefreshError.error("Couldn't obtain parameter from JSON"))
        }
    }
    
    // Use the serverAuthCode to generate a refresh and access token.
    override func generateTokens(completion:@escaping (_ success:Bool?, Swift.Error?)->()) {
        if self.serverAuthCode == nil {
            Log.error(message: "No serverAuthCode!")
            completion(false, nil)
            return
        }

        let bodyParameters = "code=\(self.serverAuthCode!)&client_id=\(Constants.session.googleClientId)&client_secret=\(Constants.session.googleClientSecret)&redirect_uri=&grant_type=authorization_code"
        Log.debug(message: "bodyParameters: \(bodyParameters)")
        
        self.googleAPICall(bodyParameters: bodyParameters) { jsonResult, error in
            guard error == nil else {
                completion(nil, error)
                return
            }
            
            if let accessToken = jsonResult?[GoogleCreds.googleAPIAccessTokenKey].string,
                let refreshToken = jsonResult?[GoogleCreds.googleAPIRefreshTokenKey].string {
                self.accessToken = accessToken
                self.refreshToken = refreshToken
                Log.debug(message: "Obtained tokens: accessToken: \(accessToken);\n refreshToken: \(refreshToken)")
                completion(true, nil)
                return
            }
            
            completion(nil, RefreshError.error("Couldn't obtain parameters from JSON"))
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
}
