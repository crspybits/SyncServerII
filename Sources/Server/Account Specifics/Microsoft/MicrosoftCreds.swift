//
//  MicrosoftCreds.swift
//  Server
//
//  Created by Christopher G Prince on 9/1/19.
//

import Foundation
import Kitura
import SyncServerShared
import LoggerAPI
import HeliumLogger

// Assumes that the microsft app has been setup as multi-tenant. E.g., see https://docs.microsoft.com/en-us/graph/auth-register-app-v2?context=graph%2Fapi%2F1.0&view=graph-rest-1.0
// Originally, I thought I had to register two apps (a server and a client)-- E.g., https://paulryan.com.au/2017/oauth-on-behalf-of-flow-adal/ HOWEVER, I have only a client iOS app registered (and using that client id and secret) and thats working.

class MicrosoftCreds : AccountAPICall, Account {
    static var accountScheme: AccountScheme = .microsoft
    
    var accountScheme: AccountScheme {
        return MicrosoftCreds.accountScheme
    }
    
    var owningAccountsNeedCloudFolderName: Bool = false
    
    var delegate: AccountDelegate?
    
    var accountCreationUser: AccountCreationUser?
    
    var accessToken: String!
    
    private(set) var refreshToken: String?
    
    override init() {
        super.init()
        baseURL = "login.microsoftonline.com/common"
    }
    
    func toJSON() -> String? {
        return nil
    }
    
    func needToGenerateTokens(dbCreds: Account?) -> Bool {
        return false
    }
    
    enum MicrosoftError: Error {
        case noAccessToken
        case noClientIdOrSecret
        case failedEncodingSecret
        case badStatusCode(HTTPStatusCode?)
        case nilAPIResult
        case noDataInResult
        case couldNotDecodeTokens
        case errorSavingCredsToDatabase
    }
    
    struct MicrosoftTokens: Decodable {
        let token_type: String
        let scope: String
        let expires_in: Int
        let ext_expires_in: Int
        let access_token: String
        let refresh_token: String
    }
    
    /// If successful, sets the `refreshToken`. The `accessToken` must be set prior to this call. The access token, when used from the iOS MSAL library must be the "idToken" and not the "accessToken". The accessToken from that library is not a JWT, and I get: AADSTS50027: JWT token is invalid or malformed.
    func generateTokens(response: RouterResponse?, completion:@escaping (Swift.Error?)->()) {
        guard let accessToken = accessToken else{
            Log.info("No accessToken from client.")
            completion(MicrosoftError.noAccessToken)
            return
        }
        
        guard let clientId = Configuration.server.MicrosoftClientId,
             let clientSecret = Configuration.server.MicrosoftClientSecret else {
            Log.error("No client id or secret.")
            completion(MicrosoftError.noClientIdOrSecret)
            return
        }
        
        // Encode the secret-- without this, my call fails with:
        // AADSTS7000215: Invalid client secret is provided.
        // See https://stackoverflow.com/questions/41133573/microsoft-graph-rest-api-invalid-client-secret
        var charSet: CharacterSet = .urlQueryAllowed
        for char in ",/?:@&=+$#" {
            if let scalar = char.unicodeScalars.first {
                charSet.remove(scalar)
            }
        }
        
        guard let clientSecretEncoded = clientSecret.addingPercentEncoding(withAllowedCharacters: charSet) else {
            completion(MicrosoftError.failedEncodingSecret)
            return
        }
        
        // https://docs.microsoft.com/en-us/azure/active-directory/develop/v2-oauth2-on-behalf-of-flow

        let grantType = "urn:ietf:params:oauth:grant-type:jwt-bearer"
        let scopes = "https://graph.microsoft.com/user.read+offline_access"
        
        let bodyParameters =
            "grant_type=\(grantType)" + "&"
            + "client_id=\(clientId)" + "&"
            + "client_secret=\(clientSecretEncoded)" + "&"
            + "assertion=\(accessToken)" + "&"
            + "scope=\(scopes)" + "&"
            + "requested_token_use=on_behalf_of"
        
        Log.debug("bodyParameters: \(bodyParameters)")
        
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
    }
    
    func merge(withNewer account: Account) {
    }
    
    static func getProperties(fromRequest request: RouterRequest) -> [String : Any] {
        return [:]
    }
    
    static func fromProperties(_ properties: AccountManager.AccountProperties, user: AccountCreationUser?, delegate: AccountDelegate?) -> Account? {
        return nil
    }
    
    static func fromJSON(_ json: String, user: AccountCreationUser, delegate: AccountDelegate?) throws -> Account? {
        return nil
    }
}

