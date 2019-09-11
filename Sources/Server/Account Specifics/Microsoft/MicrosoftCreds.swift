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
        baseURL = "login.microsoftonline.com"
    }
    
    func toJSON() -> String? {
        return nil
    }
    
    func needToGenerateTokens(dbCreds: Account?) -> Bool {
        return false
    }
    
    /// If successful, sets the `refreshToken`. The `accessToken` must be set prior to this call.
    func generateTokens(response: RouterResponse?, completion:@escaping (Swift.Error?)->()) {
        guard let accessToken = accessToken else{
            Log.info("No accessToken from client.")
            completion(nil)
            return
        }
        
        // https://docs.microsoft.com/en-us/azure/active-directory/develop/v2-oauth2-on-behalf-of-flow

        let grantType = "urn:ietf:params:oauth:grant-type:jwt-bearer"
        let clientId = ""
        let clientSecret = ""
        let scopes = ""
        
        let bodyParameters =
            "grant_type=\(grantType)" + "&"
            + "client_id=\(clientId)" + "&"
            + "client_secret=\(clientSecret)" + "&"
            + "assertion=\(accessToken)" + "&"
            + "scope=\(scopes)"
            + "requested_token_use=on_behalf_of"
        
        Log.debug("bodyParameters: \(bodyParameters)")
        
        let additionalHeaders = ["Content-Type": "application/x-www-form-urlencoded"]

        self.apiCall(method: "POST", path: "/oauth2/v2.0/token", additionalHeaders:additionalHeaders, body: .string(bodyParameters), expectedSuccessBody: .data) { apiResult, statusCode, responseHeaders in
            guard statusCode == HTTPStatusCode.OK else {
                completion(GenerateTokensError.badStatusCode(statusCode))
                return
            }
            
            /*
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
            */
        }
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

