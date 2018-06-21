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
    static var accountType:AccountType {
        return .Dropbox
    }
    
    var accountType:AccountType {
        return DropboxCreds.accountType
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
    
    override init() {
        super.init()
        baseURL = "api.dropboxapi.com"
    }
    
    func toJSON(userType: UserType) -> String? {
        assert(userType == .owning)
        
        var jsonDict = [String:String]()

        jsonDict[DropboxCreds.accessTokenKey] = self.accessToken
        // Don't need the accountId in the json because its saved as the credsId in the database.
        
        return JSONExtras.toJSONString(dict: jsonDict)
    }
    
    // Given existing Account info stored in the database, decide if we need to generate tokens. Token generation can be used for various purposes by the particular Account. E.g., For owning users to allow access to cloud storage data in offline manner. E.g., to allow access that data by sharing users.
    func needToGenerateTokens(userType:UserType, dbCreds:Account?) -> Bool {
        assert(userType == .owning)
        return false
    }
    
    private static let apiAccessTokenKey = "access_token"
    private static let apiTokenTypeKey = "token_type"
    
    func generateTokens(response: RouterResponse, completion:@escaping (Swift.Error?)->()) {
        completion(nil)
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
    
    // Only updates the user profile if the request header has the Account's specific token.
    static func updateUserProfile(_ userProfile:UserProfile, fromRequest request:RouterRequest) {
        userProfile.extendedProperties[ServerConstants.HTTPAccountIdKey] = request.headers[ServerConstants.HTTPAccountIdKey]
        userProfile.extendedProperties[ServerConstants.HTTPOAuth2AccessTokenKey] = request.headers[ServerConstants.HTTPOAuth2AccessTokenKey]
    }
    
    static func fromProfile(profile:UserProfile, user:AccountCreationUser?, delegate:AccountDelegate?) -> Account? {
        let creds = DropboxCreds()
        creds.accountCreationUser = user
        creds.delegate = delegate
        creds.accessToken =
            profile.extendedProperties[ServerConstants.HTTPOAuth2AccessTokenKey] as? String
        creds.accountId =
            profile.extendedProperties[ServerConstants.HTTPAccountIdKey] as? String
        return creds
    }
    
    static func fromJSON(_ json:String, user:AccountCreationUser, delegate:AccountDelegate?) throws -> Account? {
        guard let jsonDict = json.toJSONDictionary() as? [String:String] else {
            Log.error("Could not convert string to JSON [String:String]: \(json)")
            return nil
        }
        
        let result = DropboxCreds()
        result.delegate = delegate
        result.accountCreationUser = user
        
        // Owning users have access token's in creds.
        switch user {
        case .user(let user) where user.accountType.userType == .owning:
            fallthrough
        case .userId(_, .owning):
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
