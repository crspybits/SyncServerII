//
//  DropboxCreds.swift
//  Server
//
//  Created by Christopher G Prince on 12/3/17.
//

import Foundation
import SyncServerShared
import Kitura
import Credentials
import LoggerAPI
import KituraNet

class DropboxCreds : AccountAPICall, Account {
    static var accountScheme:AccountScheme {
        return .dropbox
    }
    
    var accountScheme:AccountScheme {
        return DropboxCreds.accountScheme
    }
    
    var owningAccountsNeedCloudFolderName: Bool {
        return false
    }
    
    weak var delegate:AccountDelegate?
    var accountCreationUser:AccountCreationUser?
    
    static let accessTokenKey = "accessToken"
    var accessToken: String!
    
    static let accountIdKey = "accountId"
    var accountId: String!
    
    override init?() {
        super.init()
        baseURL = "api.dropboxapi.com"
    }
    
    func toJSON() -> String? {
        var jsonDict = [String:String]()

        jsonDict[DropboxCreds.accessTokenKey] = self.accessToken
        // Don't need the accountId in the json because its saved as the credsId in the database.
        
        return JSONExtras.toJSONString(dict: jsonDict)
    }
    
    // Given existing Account info stored in the database, decide if we need to generate tokens. Token generation can be used for various purposes by the particular Account. E.g., For owning users to allow access to cloud storage data in offline manner. E.g., to allow access that data by sharing users.
    func needToGenerateTokens(dbCreds:Account?) -> Bool {        
        // 7/6/18; Previously, for Dropbox, I was returning false. But I want to deal with the case where a user a) deauthorizes the client app from using Dropbox, and then b) authorizes it again. This will make the access token we have in the database invalid. This will refresh it.
        return true
    }
    
    private static let apiAccessTokenKey = "access_token"
    private static let apiTokenTypeKey = "token_type"
    
    func generateTokens(response: RouterResponse?, completion:@escaping (Swift.Error?)->()) {
        // Not generating tokens, just saving.
        guard let delegate = delegate else {
            Log.warning("No Dropbox Creds delegate!")
            completion(nil)
            return
        }

        if delegate.saveToDatabase(account: self) {
            completion(nil)
            return
        }
        
        completion(GenerateTokensError.errorSavingCredsToDatabase)
    }
    
    func merge(withNewer newerAccount:Account) {
        guard let newerDropboxCreds = newerAccount as? DropboxCreds else {
            Log.error("Wrong other type of creds!")
            assert(false)
            return
        }
        
        // Both of these will be present-- both are necessary to authenticate with Dropbox.
        accountId = newerDropboxCreds.accountId
        accessToken = newerDropboxCreds.accessToken
    }
    
    static func getProperties(fromRequest request:RouterRequest) -> [String: Any] {
        var result = [String: Any]()
        
        if let accountId = request.headers[ServerConstants.HTTPAccountIdKey] {
            result[ServerConstants.HTTPAccountIdKey] = accountId
        }
        
        if let accessToken = request.headers[ServerConstants.HTTPOAuth2AccessTokenKey] {
            result[ServerConstants.HTTPOAuth2AccessTokenKey] = accessToken
        }
        
        return result
    }
    
    static func fromProperties(_ properties: AccountManager.AccountProperties, user:AccountCreationUser?, delegate:AccountDelegate?) -> Account? {
        guard let creds = DropboxCreds() else {
            return nil
        }
        
        creds.accountCreationUser = user
        creds.delegate = delegate
        creds.accessToken =
            properties.properties[ServerConstants.HTTPOAuth2AccessTokenKey] as? String
        creds.accountId =
            properties.properties[ServerConstants.HTTPAccountIdKey] as? String
        return creds
    }
    
    static func fromJSON(_ json:String, user:AccountCreationUser, delegate:AccountDelegate?) throws -> Account? {
        guard let jsonDict = json.toJSONDictionary() as? [String:String] else {
            Log.error("Could not convert string to JSON [String:String]: \(json)")
            return nil
        }
        
        guard let result = DropboxCreds() else {
            return nil
        }
        
        result.delegate = delegate
        result.accountCreationUser = user
        
        // Owning users have access token's in creds.
        switch user {
        case .user(let user) where AccountScheme(.accountName(user.accountType))?.userType == .owning:
            fallthrough
        case .userId(_):
            try setProperty(jsonDict:jsonDict, key: accessTokenKey) { value in
                result.accessToken = value
            }
            
        default:
            // Sharing users not allowed.
            assert(false)
        }
        
        return result
    }
}
