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
import KituraNet
import SyncServerShared
import Kitura
import LoggerAPI

// Credentials basis for making Google endpoint calls.

/* Analysis of credential usage for Google SignIn:

a) Upon first usage by a specific client app instance, the client will do a `checkCreds`, which will find that the user is not present on the system. It will then do an `addUser` to create the user, which will give us (the server) a serverAuthCode, which we use to generate a refreshToken and access token. Both of these are stored in the SyncServer on the database. (Note that this access token, generated from the serverAuthCode, is distinct from the access token sent from the client to the SyncServer).

    Only the `addUser` and `checkCreds` SyncServer endpoints make use of the serverAuthCode (though it is sent to all endpoints).

b) Subsequent operations pass in an access token from the client app. That client-generated access token is sent to the server for a single purpose:
    It enables primary authentication-- it is sent to Google to verify that we have an actual Google user. The lifetime of the access token when used purely in this way is uncertain. Definitely longer than 60 minutes. It might not expire. See also my comment at http://stackoverflow.com/questions/13851157/oauth2-and-google-api-access-token-expiration-time/42878810#42878810
    If primary authentication with Google fails using this access token, then a 401 HTTP status code is returned to the client app, which is its signal to, on the client-side, refresh that access token.
    
c) If the SyncServer endpoint needs to use Google Drive endpoints, the SyncServer utilizes the refresh-token based access token. (Note that not all SyncServer endpoints, e.g., /Index, connect to Google Drive).

    These refresh-token based access token's expire every 60 minutes, and we observe such expiration purely on the basis of specific failures of Google Drive endpoints-- in which case, we initiate a refresh of the access token using the refresh token, and store the refreshed access token in our SyncServer database.

d) The rationale for the two kinds of access tokens (client-side, and server-side refresh-token based) are as follows:

    i) I don't want a situation where I have to always use the client to refresh access tokens. I think this would be awkward. Operations using Google Drive would have to fail part-way through their operation when an access token expires, send an HTTP code back to the client, and then restart. This seems awkward and could make for more complicated than needed algorithms on the server.
    ii) The pattern of client-based primary authentication and server-side tokens that access cloud services is the general pattern by which the server needs to be structured. For example, for shared account authorization where Google Drive user X wants to allow a Facebook user Y to make use of their files, primary authentication will take place using Facebook credentials for Y, and server-side use of Google Drive will make use of X's stored refresh token/access token's.
*/

class GoogleCreds : AccountAPICall, Account {    
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
    
    var owningAccountsNeedCloudFolderName: Bool {
        return true
    }
    
    static var accountType:AccountType {
        return .Google
    }
    
    var accountType:AccountType {
        return GoogleCreds.accountType
    }

    weak var delegate:AccountDelegate?
    var accountCreationUser:AccountCreationUser?
    
    // This is to ensure that some error doesn't cause us to attempt to refresh the access token multiple times in a row. I'm assuming that for any one endpoint invocation, we'll at most need to refresh the access token a single time.
    private var alreadyRefreshed = false
    
    override init() {
        super.init()
        baseURL = "www.googleapis.com"
    }
    
    static func getProperties(fromRequest request:RouterRequest) -> [String: Any] {
        var result = [String: Any]()
        
        if let authCode = request.headers[ServerConstants.HTTPOAuth2AuthorizationCodeKey] {
            result[ServerConstants.HTTPOAuth2AuthorizationCodeKey] = authCode
        }
        
        if let accessToken = request.headers[ServerConstants.HTTPOAuth2AccessTokenKey] {
            result[ServerConstants.HTTPOAuth2AccessTokenKey] = accessToken
        }
        
        return result
    }
    
    static func fromProperties(_ properties: AccountManager.AccountProperties, user:AccountCreationUser?, delegate:AccountDelegate?) -> Account? {
        let creds = GoogleCreds()
        creds.accountCreationUser = user
        creds.delegate = delegate
        creds.accessToken =
            properties.properties[ServerConstants.HTTPOAuth2AccessTokenKey] as? String
        creds.serverAuthCode =
            properties.properties[ServerConstants.HTTPOAuth2AuthorizationCodeKey] as? String
        return creds
    }
    
    static func fromJSON(_ json:String, user:AccountCreationUser, delegate:AccountDelegate?) throws -> Account? {
        guard let jsonDict = json.toJSONDictionary() as? [String:String] else {
            Log.error("Could not convert string to JSON [String:String]: \(json)")
            return nil
        }
        
        let result = GoogleCreds()
        result.delegate = delegate
        result.accountCreationUser = user
        
        // Only owning users have access token's in creds. Sharing users have empty creds stored in the database.
        switch user {
        case .user(let user) where user.accountType.userType == .owning:
            fallthrough
        case .userId(_, .owning):
            try setProperty(jsonDict:jsonDict, key: accessTokenKey) { value in
                result.accessToken = value
            }
            
        default:
            break
        }
        
        // Considering the refresh token and serverAuthCode as optional because (a) I think I don't always get these from the client, and (b) during testing, I don't always have these.
        
        try setProperty(jsonDict:jsonDict, key: refreshTokenKey, required:false) { value in
            result.refreshToken = value
        }
        
        try setProperty(jsonDict:jsonDict, key: serverAuthCodeKey, required:false) { value in
            result.serverAuthCode = value
        }
        
        return result
    }
    
    func toJSON(userType: UserType) -> String? {
        var jsonDict = [String:String]()
        
        // 8/8/17; Only if a Google user is an owning user should we be storing creds info into the database. https://github.com/crspybits/SyncServerII/issues/13
        // 6/23/18; Now-- we've changed the concept of owning versus sharing. Google accounts are always owning. See also https://github.com/crspybits/SyncServerII/issues/27
        jsonDict[GoogleCreds.accessTokenKey] = self.accessToken
        jsonDict[GoogleCreds.refreshTokenKey] = self.refreshToken
        jsonDict[GoogleCreds.serverAuthCodeKey] = self.serverAuthCode

        return JSONExtras.toJSONString(dict: jsonDict)
    }
    
    static let googleAPIAccessTokenKey = "access_token"
    static let googleAPIRefreshTokenKey = "refresh_token"
    
    func needToGenerateTokens(userType:UserType, dbCreds:Account? = nil) -> Bool {
        // 7/6/18; Google Drive accounts are always owning.
        assert(userType == .owning)

        var result = serverAuthCode != nil
            
        // If no dbCreds, then we generate tokens.
        if let dbCreds = dbCreds {
            if let dbGoogleCreds = dbCreds as? GoogleCreds {
                result = result && serverAuthCode != dbGoogleCreds.serverAuthCode
            }
            else {
                Log.error("Did not get GoogleCreds as dbCreds!")
            }
        }
        
        Log.debug("needToGenerateTokens: \(result); serverAuthCode: \(String(describing: serverAuthCode))")
        return result
    }
    
    // Use the serverAuthCode to generate a refresh and access token if there is one.
    func generateTokens(response: RouterResponse, completion:@escaping (Swift.Error?)->()) {
        if self.serverAuthCode == nil {
            Log.info("No serverAuthCode from client.")
            completion(nil)
            return
        }

        let bodyParameters = "code=\(self.serverAuthCode!)&client_id=\(Constants.session.googleClientId!)&client_secret=\(Constants.session.googleClientSecret!)&redirect_uri=&grant_type=authorization_code"
        Log.debug("bodyParameters: \(bodyParameters)")
        
        let additionalHeaders = ["Content-Type": "application/x-www-form-urlencoded"]

        self.apiCall(method: "POST", path: "/oauth2/v4/token", additionalHeaders:additionalHeaders, body: .string(bodyParameters)) { apiResult, statusCode, responseHeaders in
            guard statusCode == HTTPStatusCode.OK else {
                completion(GenerateTokensError.badStatusCode(statusCode))
                return
            }
            
            guard apiResult != nil else {
                completion(GenerateTokensError.nilAPIResult)
                return
            }
            
            if case .dictionary(let dictionary) = apiResult!,
                let accessToken = dictionary[GoogleCreds.googleAPIAccessTokenKey] as? String,
                let refreshToken = dictionary[GoogleCreds.googleAPIRefreshTokenKey] as? String {
                
                self.accessToken = accessToken
                self.refreshToken = refreshToken
                Log.debug("Obtained tokens: accessToken: \(accessToken)\n refreshToken: \(refreshToken)")
                
                if self.delegate == nil {
                    Log.warning("No Google Creds delegate!")
                    completion(nil)
                    return
                }
                
                if self.delegate!.saveToDatabase(account: self) {
                    completion(nil)
                    return
                }
                
                completion(GenerateTokensError.errorSavingCredsToDatabase)
                return
            }
            
            completion(GenerateTokensError.couldNotObtainParameterFromJSON)
        }
    }
    
    func merge(withNewer newerAccount:Account) {
        assert(newerAccount is GoogleCreds, "Wrong other type of creds!")
        let newerGoogleCreds = newerAccount as! GoogleCreds
        
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
    case noRefreshToken
    case expiredOrRevokedAccessToken
    }
    
    // Use the refresh token to generate a new access token.
    // If error is nil when the completion handler is called, then the accessToken of this object has been refreshed. It hasn't yet been persistently stored on this server. Uses delegate, if one is defined, to save refreshed creds to database.
    func refresh(completion:@escaping (Swift.Error?)->()) {
        // See "Using a refresh token" at https://developers.google.com/identity/protocols/OAuth2WebServer

        // TODO: *0* Sometimes we've been ending up in a situation where we don't have a refresh token. The database somehow doesn't get the refresh token saved in certain situations. What are those situations?
        guard self.refreshToken != nil else {
            completion(RefreshError.noRefreshToken)
            return
        }
        
        let bodyParameters = "client_id=\(Constants.session.googleClientId!)&client_secret=\(Constants.session.googleClientSecret!)&refresh_token=\(self.refreshToken!)&grant_type=refresh_token"
        Log.debug("bodyParameters: \(bodyParameters)")
        
        let additionalHeaders = ["Content-Type": "application/x-www-form-urlencoded"]
        
        self.apiCall(method: "POST", path: "/oauth2/v4/token", additionalHeaders:additionalHeaders, body: .string(bodyParameters), expectedFailureBody: .json) { apiResult, statusCode, responseHeaders in

            // When the refresh token has been revoked
            // ["error": "invalid_grant", "error_description": "Token has been expired or revoked."]
            
            // [1]
            if statusCode == HTTPStatusCode.badRequest,
                case .dictionary(let dict)? = apiResult,
                let error = dict["error"] as? String,
                error == "invalid_grant" {
                
                completion(RefreshError.expiredOrRevokedAccessToken)
                return
            }

            guard statusCode == HTTPStatusCode.OK else {
                Log.error("Bad status code: \(String(describing: statusCode))")
                completion(RefreshError.badStatusCode(statusCode))
                return
            }
            
            guard apiResult != nil else {
                Log.error("API result was nil!")
                completion(RefreshError.nilAPIResult)
                return
            }
            
            guard case .dictionary(let dictionary) = apiResult! else {
                Log.error("Bad JSON result: \(String(describing: apiResult))")
                completion(RefreshError.badJSONResult)
                return
            }
            
            if let accessToken = dictionary[GoogleCreds.googleAPIAccessTokenKey] as? String {
                self.accessToken = accessToken
                Log.debug("Refreshed access token: \(accessToken)")
                
                if self.delegate == nil {
                    Log.warning("Delegate was nil-- could not save creds to database!")
                    completion(nil)
                    return
                }
                
                if self.delegate!.saveToDatabase(account: self) {
                    completion(nil)
                    return
                }
                
                completion(RefreshError.errorSavingCredsToDatabase)
                return
            }
            
            Log.error("Could not obtain parameter from JSON!")
            completion(RefreshError.couldNotObtainParameterFromJSON)
        }
    }
    
    let tokenRevokedOrExpired = "accessTokenRevokedOrExpired"
    
    override func apiCall(method:String, baseURL:String? = nil, path:String,
                 additionalHeaders: [String:String]? = nil, urlParameters:String? = nil,
                 body:APICallBody? = nil,
                 returnResultWhenNon200Code:Bool = true,
                 expectedSuccessBody:ExpectedResponse? = nil,
                 expectedFailureBody:ExpectedResponse? = nil,
        completion:@escaping (_ result: APICallResult?, HTTPStatusCode?, _ responseHeaders: HeadersContainer?)->()) {
        
        var headers:[String:String] = additionalHeaders ?? [:]
        
        // We use this for some cases where we don't have an accessToken
        if self.accessToken != nil {
            headers["Authorization"] = "Bearer \(self.accessToken!)"
        }

        super.apiCall(method: method, baseURL: baseURL, path: path, additionalHeaders: headers, urlParameters: urlParameters, body: body, expectedSuccessBody: expectedSuccessBody, expectedFailureBody: expectedFailureBody) { (apiCallResult, statusCode, responseHeaders) in
        
            /* So far, I've seen two results from a Google expired or revoked refresh token:
                1) an unauthorized http status here followed by [1] in refresh.
                2) The following response here:
                    ["error":
                        ["code": 403,
                         "message": "Daily Limit for Unauthenticated Use Exceeded. Continued use requires signup.",
                         "errors":
                            [
                                ["message": "Daily Limit for Unauthenticated Use Exceeded. Continued use requires signup.",
                                "reason": "dailyLimitExceededUnreg",
                                "extendedHelp": "https://code.google.com/apis/console",
                                "domain": "usageLimits"]
                            ]
                        ]
                    ]
            */
            
            if statusCode == HTTPStatusCode.forbidden,
                case .dictionary(let dict)? = apiCallResult,
                let error = dict["error"] as? [String: Any],
                let errors = error["errors"] as? [[String: Any]],
                errors.count > 0,
                let reason = errors[0]["reason"] as? String,
                reason == "dailyLimitExceededUnreg" {
                
                Log.info("Google API Call: Daily limit exceeded.")
                
                completion(APICallResult.dictionary(
                    ["error":self.tokenRevokedOrExpired]),
                    .forbidden, nil)
                return
            }
            
            if statusCode == self.expiredAccessTokenHTTPCode && !self.alreadyRefreshed {
                self.alreadyRefreshed = true
                Log.info("Attempting to refresh access token...")
                
                self.refresh() { error in
                    if let error = error {
                        switch error {
                        case RefreshError.expiredOrRevokedAccessToken:
                            Log.info("Refresh token expired or revoked")
                            completion(
                                APICallResult.dictionary(
                                    ["error":self.tokenRevokedOrExpired]),
                                .unauthorized, nil)
                        default:
                            Log.error("Failed to refresh access token: \(String(describing: error))")
                        }
                    }
                    else {
                        Log.info("Successfully refreshed access token!")

                        // Refresh was successful, update the authorization header and try the operation again.
                        headers["Authorization"] = "Bearer \(self.accessToken!)"

                        super.apiCall(method: method, baseURL: baseURL, path: path, additionalHeaders: headers, urlParameters: urlParameters, body: body, expectedSuccessBody: expectedSuccessBody, expectedFailureBody: expectedFailureBody, completion: completion)
                    }
                }
            }
            else {
                completion(apiCallResult, statusCode, responseHeaders)
            }
        }
    }
}
