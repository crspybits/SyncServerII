//
//  MicrosoftCreds.swift
//  Server
//
//  Created by Christopher G Prince on 9/1/19.
//

import Foundation
import Kitura
import ServerShared
import LoggerAPI
import HeliumLogger
import KituraNet
import Credentials

// Assumes that the microsft app has been registered as multi-tenant. E.g., see https://docs.microsoft.com/en-us/graph/auth-register-app-v2?context=graph%2Fapi%2F1.0&view=graph-rest-1.0
// Originally, I thought I had to register two apps (a server and a client)-- E.g., https://paulryan.com.au/2017/oauth-on-behalf-of-flow-adal/ HOWEVER, I have only a client iOS app registered (and using that client id and secret) and thats working.

class MicrosoftCreds : AccountAPICall, Account {
    static var accountScheme: AccountScheme = .microsoft
    
    var accountScheme: AccountScheme {
        return MicrosoftCreds.accountScheme
    }
    
    var owningAccountsNeedCloudFolderName: Bool = false
    
    var delegate: AccountDelegate?
    
    var accountCreationUser: AccountCreationUser?

    // Don't use the "accessToken" from the iOS MSAL for this; use the iOS MSAL idToken.
    var accessToken: String!
    
    var refreshToken: String?
    
    private var alreadyRefreshed = false

    private let scopes = "https://graph.microsoft.com/user.read+offline_access"

    override init?() {
        super.init()
        baseURL = "login.microsoftonline.com/common"
    }
    
    func needToGenerateTokens(dbCreds: Account?) -> Bool {
        // If we get fancy, eventually we could look at the expiry date/time in the JWT access token and estimate if we need to generate tokens.
        return true
    }
    
    enum MicrosoftError: Swift.Error {
        case noAccessToken
        case failedGettingClientIdOrSecret
        case badStatusCode(HTTPStatusCode?)
        case nilAPIResult
        case noDataInResult
        case couldNotDecodeTokens
        case errorSavingCredsToDatabase
        case noRefreshToken
    }
    
    struct MicrosoftTokens: Decodable {
        let token_type: String
        let scope: String
        let expires_in: Int
        let ext_expires_in: Int
        let access_token: String
        let refresh_token: String
    }
    
    private struct ClientInfo {
        let id: String
        let secret: String
    }
        
    func encoded(string: String, baseCharSet: CharacterSet = .urlQueryAllowed, additionalExcludedCharacters: String? = nil) -> String? {
        var charSet: CharacterSet = baseCharSet
        
        if let additionalExcludedCharacters = additionalExcludedCharacters {
            for char in additionalExcludedCharacters {
                if let scalar = char.unicodeScalars.first {
                    charSet.remove(scalar)
                }
            }
        }
        
        return string.addingPercentEncoding(withAllowedCharacters: charSet)
    }
    
    private func getClientInfo() -> ClientInfo? {
        guard let clientId = Configuration.server.MicrosoftClientId,
             let clientSecret = Configuration.server.MicrosoftClientSecret else {
            Log.error("No client id or secret.")
            return nil
        }
        
        // Encode the secret-- without this, my call fails with:
        // AADSTS7000215: Invalid client secret is provided.
        // See https://stackoverflow.com/questions/41133573/microsoft-graph-rest-api-invalid-client-secret
        guard let clientSecretEncoded = encoded(string: clientSecret, additionalExcludedCharacters: ",/?:@&=+$#") else {
            Log.error("Failed encoding client secret.")
            return nil
        }
        
        return ClientInfo(id: clientId, secret: clientSecretEncoded)
    }
    
    /// If successful, sets the `refreshToken`. The `accessToken` must be set prior to this call. The access token, when used from the iOS MSAL library, must be the "idToken" and not the iOS MSAL "accessToken". The accessToken from the iOS MSAL library is not a JWT -- when I use it I get: "AADSTS50027: JWT token is invalid or malformed".
    func generateTokens(completion:@escaping (Swift.Error?)->()) {
        guard let accessToken = accessToken else{
            Log.info("No accessToken from client.")
            completion(MicrosoftError.noAccessToken)
            return
        }
        
        guard let clientInfo = getClientInfo() else {
            completion(MicrosoftError.failedGettingClientIdOrSecret)
            return
        }
        
        // https://docs.microsoft.com/en-us/azure/active-directory/develop/v2-oauth2-on-behalf-of-flow

        let grantType = "urn:ietf:params:oauth:grant-type:jwt-bearer"
        let scopes = "https://graph.microsoft.com/user.read+offline_access"
        
        let bodyParameters =
            "grant_type=\(grantType)" + "&"
            + "client_id=\(clientInfo.id)" + "&"
            + "client_secret=\(clientInfo.secret)" + "&"
            + "assertion=\(accessToken)" + "&"
            + "scope=\(scopes)" + "&"
            + "requested_token_use=on_behalf_of"
        
        // Log.debug("bodyParameters: \(bodyParameters)")
        
        let additionalHeaders = ["Content-Type": "application/x-www-form-urlencoded"]

        self.apiCall(method: "POST", path: "/oauth2/v2.0/token", additionalHeaders:additionalHeaders, body: .string(bodyParameters), expectedSuccessBody: .data) { apiResult, statusCode, responseHeaders in

            guard statusCode == HTTPStatusCode.OK else {
                completion(MicrosoftError.badStatusCode(statusCode))
                return
            }
            
            guard let apiResult = apiResult else {
                completion(MicrosoftError.nilAPIResult)
                return
            }
            
            guard case .data(let data) = apiResult else {
                completion(MicrosoftError.noDataInResult)
                return
            }
            
            let tokens: MicrosoftTokens
            
            let decoder = JSONDecoder()
            do {
                tokens = try decoder.decode(MicrosoftTokens.self, from: data)
            } catch let error {
                Log.error("Error decoding token result: \(error)")
                completion(MicrosoftError.couldNotDecodeTokens)
                return
            }
            
            self.accessToken = tokens.access_token
            self.refreshToken = tokens.refresh_token

            guard let delegate = self.delegate else {
                Log.warning("No Microsoft Creds delegate!")
                completion(nil)
                return
            }
            
            if delegate.saveToDatabase(account: self) {
                completion(nil)
            } else {
                completion(MicrosoftError.errorSavingCredsToDatabase)
            }
        }
    }
    
    // Use the refresh token to generate a new access token.
    // If error is nil when the completion handler is called, then the accessToken of this object has been refreshed. Uses delegate, if one is defined, to save refreshed creds to database.
    func refresh(completion:@escaping (Swift.Error?)->()) {
        // https://docs.microsoft.com/en-us/azure/active-directory/develop/v2-oauth2-auth-code-flow
        
        guard let refreshToken = refreshToken else {
            completion(MicrosoftError.noRefreshToken)
            return
        }
        
        guard let clientInfo = getClientInfo() else {
            completion(MicrosoftError.failedGettingClientIdOrSecret)
            return
        }

        let grantType = "refresh_token"
        
        let bodyParameters =
            "grant_type=\(grantType)" + "&"
            + "client_id=\(clientInfo.id)" + "&"
            + "client_secret=\(clientInfo.secret)" + "&"
            + "scope=\(scopes)" + "&"
            + "refresh_token=\(refreshToken)"

        // Log.debug("bodyParameters: \(bodyParameters)")
        
        let additionalHeaders = ["Content-Type": "application/x-www-form-urlencoded"]
        
        self.apiCall(method: "POST", path: "/oauth2/v2.0/token", additionalHeaders:additionalHeaders, body: .string(bodyParameters), expectedSuccessBody: .data, expectedFailureBody: .json) { apiResult, statusCode, responseHeaders in

            guard statusCode == HTTPStatusCode.OK else {
                Log.error("Bad status code: \(String(describing: statusCode))")
                completion(MicrosoftError.badStatusCode(statusCode))
                return
            }
            
            guard let apiResult = apiResult else {
                Log.error("API result was nil!")
                completion(MicrosoftError.nilAPIResult)
                return
            }
            
            guard case .data(let data) = apiResult else {
                completion(MicrosoftError.noDataInResult)
                return
            }
            
            let tokens: MicrosoftTokens
            
            let decoder = JSONDecoder()
            do {
                tokens = try decoder.decode(MicrosoftTokens.self, from: data)
            } catch let error {
                Log.error("Error decoding token result: \(error)")
                completion(MicrosoftError.couldNotDecodeTokens)
                return
            }
            
            // Log.debug("tokens.access_token: \(tokens.access_token)")
            
            self.accessToken = tokens.access_token
            self.refreshToken = tokens.refresh_token

            guard let delegate = self.delegate else {
                Log.warning("No Microsoft Creds delegate!")
                completion(nil)
                return
            }
            
            if delegate.saveToDatabase(account: self) {
                completion(nil)
            } else {
                completion(MicrosoftError.errorSavingCredsToDatabase)
            }
        }
    }
    
    func merge(withNewer account: Account) {
        guard let newerCreds = account as? MicrosoftCreds else {
            assertionFailure("Wrong other type of creds!")
            return
        }
        
        if let refreshToken = newerCreds.refreshToken {
            self.refreshToken = refreshToken
        }
        
        if let accessToken = newerCreds.accessToken {
            self.accessToken = accessToken
        }
    }
    
    static func getProperties(fromHeaders headers:AccountHeaders) -> [String: Any] {
        var result = [String: Any]()
        
        if let accessToken = headers[ServerConstants.HTTPOAuth2AccessTokenKey] {
            result[ServerConstants.HTTPOAuth2AccessTokenKey] = accessToken
        }
        
        return result
    }
    
    static func fromProperties(_ properties: AccountProperties, user:AccountCreationUser?, delegate:AccountDelegate?) -> Account? {
        guard let creds = MicrosoftCreds() else {
            return nil
        }
        
        creds.accountCreationUser = user
        creds.delegate = delegate
        creds.accessToken =
            properties.properties[ServerConstants.HTTPOAuth2AccessTokenKey] as? String
        return creds
    }
    
    func toJSON() -> String? {
        var jsonDict = [String:String]()
        
        jsonDict[MicrosoftCreds.accessTokenKey] = self.accessToken
        jsonDict[MicrosoftCreds.refreshTokenKey] = self.refreshToken

        return JSONExtras.toJSONString(dict: jsonDict)
    }
    
    static func fromJSON(_ json: String, user: AccountCreationUser, delegate: AccountDelegate?) throws -> Account? {
        guard let jsonDict = json.toJSONDictionary() as? [String:String] else {
            Log.error("Could not convert string to JSON [String:String]: \(json)")
            return nil
        }
        
        guard let result = MicrosoftCreds() else {
            return nil
        }
        
        result.delegate = delegate
        result.accountCreationUser = user
        
        switch user {
        case .user(let user) where AccountScheme(.accountName(user.accountType))?.userType == .owning:
            fallthrough
        case .userId:
            try setProperty(jsonDict:jsonDict, key: accessTokenKey) { value in
                result.accessToken = value
            }
            
        default:
            // Sharing users not allowed.
            assert(false)
        }
        
        try setProperty(jsonDict:jsonDict, key: refreshTokenKey, required:false) { value in
            result.refreshToken = value
        }
        
        return result
    }
    
    override func apiCall(method:String, baseURL:String? = nil, path:String,
                 additionalHeaders: [String:String]? = nil, additionalOptions: [ClientRequest.Options] = [], urlParameters:String? = nil,
                 body:APICallBody? = nil,
                 returnResultWhenNon200Code:Bool = true,
                 expectedSuccessBody:ExpectedResponse? = nil,
                 expectedFailureBody:ExpectedResponse? = nil,
        completion:@escaping (_ result: APICallResult?, HTTPStatusCode?, _ responseHeaders: HeadersContainer?)->()) {

        super.apiCall(method: method, baseURL: baseURL, path: path, additionalHeaders: additionalHeaders, additionalOptions: additionalOptions, urlParameters: urlParameters, body: body,
            returnResultWhenNon200Code: returnResultWhenNon200Code,
            expectedSuccessBody: expectedSuccessBody,
            expectedFailureBody: expectedFailureBody) { (apiCallResult, statusCode, responseHeaders) in
            
            var headers:[String:String] = additionalHeaders ?? [:]
            
            if self.expiredAccessToken(apiResult: apiCallResult, statusCode: statusCode) && !self.alreadyRefreshed {
                self.alreadyRefreshed = true
                Log.info("Attempting to refresh Microsoft access token...")
                
                self.refresh() { error in
                    if let error = error {
                        let message = "Failed refreshing access token: \(error)"
                        let errorResult = ErrorResult(error: MicrosoftCreds.ErrorResult.TheError(code: MicrosoftCreds.ErrorResult.invalidAuthToken, message: message))
                        
                        let encoder = JSONEncoder()
                        guard let response = try? encoder.encode(errorResult) else {
                            completion( APICallResult.dictionary(["error": message]),
                                .unauthorized, nil)
                            return
                        }
                        
                        Log.error("\(message)")
                        completion(APICallResult.data(response), .unauthorized, nil)
                    }
                    else {
                        Log.info("Successfully refreshed access token!")

                        // Refresh was successful, update the authorization header and try the operation again.
                        headers["Authorization"] = "Bearer \(self.accessToken!)"
                        
                        super.apiCall(method: method, baseURL: baseURL, path: path, additionalHeaders: headers, additionalOptions: additionalOptions, urlParameters: urlParameters, body: body, returnResultWhenNon200Code: returnResultWhenNon200Code, expectedSuccessBody: expectedSuccessBody, expectedFailureBody: expectedFailureBody, completion: completion)
                    }
                }
            }
            else {
                completion(apiCallResult, statusCode, responseHeaders)
            }
        }
    }
    
    private func expiredAccessToken(apiResult: APICallResult?, statusCode: HTTPStatusCode?) -> Bool {
        guard let apiResult = apiResult else {
            return false
        }

        guard case .data(let data) = apiResult else {
            return false
        }

        let decoder = JSONDecoder()
        guard let errorResult = try? decoder.decode(ErrorResult.self, from: data) else {
            return false
        }

        return self.accessTokenIsRevokedOrExpired(errorResult: errorResult, statusCode: statusCode)
    }
}

