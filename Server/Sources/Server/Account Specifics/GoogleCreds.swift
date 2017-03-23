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

/* Analysis of credential usage for Google SignIn:

a) Upon first usage by a specific client app instance, the client will do a `checkCreds`, which will find that the user is not present on the system. It will then do an `addUser` to create the user, which will give us (the server) a serverAuthCode, which we use to generate a refreshToken and access token. Both of these are stored in the SyncServer on the database. (Note that this access token, generated from the serverAuthCode, is distinct from the access token sent from the client to the SyncServer).

    Only the `addUser` and `checkCreds` SyncServer endpoints make use of the serverAuthCode (though it is sent to all endpoints).

b) Subsequent operations pass in an access token from the client app. That client-generated access token is sent to the server for a single purpose:
    It enables primary authentication-- it is sent to Google to verify that we have an actual Google user. The lifetime of the access token when used purely in this way is uncertain. Definitely longer than 60 minutes. It might not expire. See also my comment at http://stackoverflow.com/questions/13851157/oauth2-and-google-api-access-token-expiration-time/42878810#42878810
    If primary authentication with Google fails using this access token, then a 401 HTTP status code is returned to the client app, which is its signal to, on the client-side, refresh that access token.
    
c) If the SyncServer endpoint needs to use Google Drive endpoints, the SyncServer utilizes the refresh-token based access token. (Note that not all SyncServer endpoints, e.g., /FileIndex, connect to Google Drive).

    These refresh-token based access token's expire every 60 minutes, and we observe such expiration purely on the basis of specific failures of Google Drive endpoints-- in which case, we initiate a refresh of the access token using the refresh token, and store the refreshed access token in our SyncServer database.

d) The rationale for the two kinds of access tokens (client-side, and server-side refresh-token based) are as follows:

    i) I don't want a situation where I have to always use the client to refresh access tokens. I think this would be awkward. Operations using Google Drive would have to fail part-way through their operation when an access token expires, send an HTTP code back to the client, and then restart. This seems awkward and could make for more complicated than needed algorithms on the server.
    ii) The pattern of client-based primary authentication and server-side tokens that access cloud services is the general pattern by which the server needs to be structured. For example, for shared account authorization where Google Drive user X wants to allow a Facebook user Y to make use of their files, primary authentication will take place using Facebook credentials for Y, and server-side use of Google Drive will make use of X's stored refresh token/access token's.
*/

class GoogleCreds : Creds {
    // The following keys are for conversion <-> JSON (e.g., to store this into a database).
    
    static let accessTokenKey = "accessToken"
    var accessToken: String!
    
    static let refreshTokenKey = "refreshToken"
    // This is obtained via the serverAuthCode
    var refreshToken: String!
    
    // Storing the serverAuthCode in the database so that I don't try to generate a refresh token from the same serverAuthCode twice.
    static let serverAuthCodeKey = "serverAuthCode"
    // Only present transiently.
    var serverAuthCode:String?
    
    let expiredAccessTokenHTTPCode = HTTPStatusCode.unauthorized
    
    // This is to ensure that some error doesn't cause us to attempt to refresh the access token multiple times in a row. I'm assuming that for any one endpoint invocation, we'll at most need to refresh the access token a single time.
    private var alreadyRefreshed = false
    
    override init() {
        super.init()
        self.accountType = .Google
        self.baseURL = "www.googleapis.com"
    }
    
    enum FromJSONError : Swift.Error {
    case noRequiredKeyValue
    }
    
    override static func fromJSON(s:String) throws -> Creds? {
        guard let jsonDict = s.toJSONDictionary() as? [String:String] else {
            Log.error(message: "Could not convert string to JSON [String:String]: \(s)")
            return nil
        }
        
        func setProperty(key:String, required:Bool=true, setWithValue:(String)->()) throws {
            let keyValue = jsonDict[key]
            if keyValue == nil {
                if required {
                    Log.error(message: "No \(key) value present.")
                    throw FromJSONError.noRequiredKeyValue
                }
                else {
                    Log.warning(message: "No \(key) value present.")
                }
            }
            else {
                setWithValue(keyValue!)
            }
        }
        
        let result = GoogleCreds()
        
        try setProperty(key: accessTokenKey) { value in
            result.accessToken = value
        }
        
        // Considering the refresh token and serverAuthCode as optional because (a) I think I don't always get these from the client, and (b) during testing, I don't always have these.
        
        try setProperty(key: refreshTokenKey, required:false) { value in
            result.refreshToken = value
        }
        
        try setProperty(key: serverAuthCodeKey, required:false) { value in
            result.serverAuthCode = value
        }
        
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
        jsonDict[GoogleCreds.serverAuthCodeKey] = self.serverAuthCode
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
    case errorSavingCredsToDatabase
    }
    
    override func needToGenerateTokens(dbCreds:Creds) -> Bool {
        let dbGoogleCreds = dbCreds as! GoogleCreds
        return serverAuthCode != nil && serverAuthCode != dbGoogleCreds.serverAuthCode
    }
    
    // Use the serverAuthCode to generate a refresh and access token if there is one. If no error occurs, success is true iff the generation occurred successfully.
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
                
                if self.delegate == nil || self.delegate!.saveToDatabase(creds: self) {
                    completion(true, nil)
                    return
                }
                
                completion(nil, GenerateTokensError.errorSavingCredsToDatabase)
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
        
        if newerGoogleCreds.serverAuthCode != nil {
            self.serverAuthCode = newerGoogleCreds.serverAuthCode
        }
        
        self.accessToken = newerGoogleCreds.accessToken
    }
    
    enum RefreshError : Swift.Error {
    case badStatusCode(HTTPStatusCode?)
    case couldNotObtainParameterFromJSON
    case nilAPIResult
    case badJSONResult
    case errorSavingCredsToDatabase
    }
    
    // Use the refresh token to generate a new access token.
    // If error is nil when the completion handler is called, then the accessToken of this object has been refreshed. It hasn't yet been persistently stored on this server. Uses delegate, if one is defined, to save refreshed creds to database.
    func refresh(completion:@escaping (Swift.Error?)->()) {
        // See "Using a refresh token" at https://developers.google.com/identity/protocols/OAuth2WebServer

        let bodyParameters = "client_id=\(Constants.session.googleClientId)&client_secret=\(Constants.session.googleClientSecret)&refresh_token=\(self.refreshToken!)&grant_type=refresh_token"
        Log.debug(message: "bodyParameters: \(bodyParameters)")
        
        let additionalHeaders = ["Content-Type": "application/x-www-form-urlencoded"]
        
        self.apiCall(method: "POST", path: "/oauth2/v4/token", additionalHeaders:additionalHeaders, body: .string(bodyParameters)) { apiResult, statusCode in
            guard statusCode == HTTPStatusCode.OK else {
                Log.error(message: "Bad status code: \(statusCode)")
                completion(RefreshError.badStatusCode(statusCode))
                return
            }
            
            guard apiResult != nil else {
                Log.error(message: "API result was nil!")
                completion(RefreshError.nilAPIResult)
                return
            }
            
            guard case .json(let jsonResult) = apiResult! else {
                Log.error(message: "Bad JSON result: \(apiResult)")
                completion(RefreshError.badJSONResult)
                return
            }
            
            if let accessToken =
                jsonResult[GoogleCreds.googleAPIAccessTokenKey].string {
                self.accessToken = accessToken
                Log.debug(message: "Refreshed access token: \(accessToken)")
                
                if self.delegate == nil || self.delegate!.saveToDatabase(creds: self) {
                    completion(nil)
                    return
                }
                
                completion(RefreshError.errorSavingCredsToDatabase)
                return
            }
            
            Log.error(message: "Could not obtain parameter from JSON!")
            completion(RefreshError.couldNotObtainParameterFromJSON)
        }
    }
    
    override func apiCall(method:String, baseURL:String? = nil, path:String,
        additionalHeaders: [String:String]? = nil, urlParameters:String? = nil, body:Body? = nil,
        completion:@escaping (_ result: APICallResult?, HTTPStatusCode?)->()) {
        
        var headers:[String:String] = additionalHeaders ?? [:]
        
        // We use this for some cases where we don't have an accessToken
        if self.accessToken != nil {
            headers["Authorization"] = "Bearer \(self.accessToken!)"
        }

        super.apiCall(method: method, baseURL: baseURL, path: path, additionalHeaders: headers, urlParameters: urlParameters, body: body) { (apiCallResult, statusCode) in
        
            if statusCode == self.expiredAccessTokenHTTPCode && !self.alreadyRefreshed {
                self.alreadyRefreshed = true
                Log.info(message: "Attempting to refresh access token...")
                
                self.refresh() { error in
                    if error == nil {
                        Log.info(message: "Successfully refreshed access token!")

                        // Refresh was successful, update the authorization header and try the operation again.
                        headers["Authorization" ] = "Bearer \(self.accessToken!)"

                        super.apiCall(method: method, baseURL: baseURL, path: path, additionalHeaders: headers, urlParameters: urlParameters, body: body, completion: completion)
                    }
                    else {
                        Log.error(message: "Failed to refresh access token: \(error)")
                        completion(nil, .internalServerError)
                    }
                }
            }
            else {
                completion(apiCallResult, statusCode)
            }
        }
    }
}
