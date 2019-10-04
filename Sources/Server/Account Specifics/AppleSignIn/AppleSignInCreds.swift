//
//  AppleSignInCreds.swift
//  Server
//
//  Created by Christopher G Prince on 10/2/19.
//

import Foundation
import CredentialsAppleSignIn
import SyncServerShared
import Kitura
import HeliumLogger
import LoggerAPI

class AppleSignInCreds: AccountAPICall, Account {
    static let accountScheme: AccountScheme = .appleSignIn
    let accountScheme: AccountScheme = AppleSignInCreds.accountScheme
    let owningAccountsNeedCloudFolderName: Bool = false
    
    weak var delegate: AccountDelegate?
    
    var accountCreationUser: AccountCreationUser?
    
    struct DatabaseCreds: Codable {
        // Storing the serverAuthCode in the database so that I don't try to generate a refresh token from the same serverAuthCode twice.
        let serverAuthCode: String?
        
        let idToken: String
        let refreshToken: String?
        
        // Because Apple imposes limits about how often you can use the refresh token.
        let lastRefreshTokenUsage: Date?
    }
    
    var accessToken: String!
    private var serverAuthCode:String?
    
    // Obtained via the serverAuthCode
    private var refreshToken: String?
    
    // Loaded from the database.
    private var databaseCreds: DatabaseCreds?
    
    override init() {
        super.init()
        baseURL = ""
    }
    
    func needToGenerateTokens(dbCreds: Account?) -> Bool {
        return false
    }
    
    /// This does one of two things:
    /// 1) If there is an serverAuthCode, it uses that to generate a refresh token.
    /// 2) If there
    func generateTokens(response: RouterResponse?, completion: @escaping (Error?) -> ()) {
    }
    
    func merge(withNewer account: Account) {
    }
    
    static func getProperties(fromRequest request:RouterRequest) -> [String: Any] {
        var result = [String: Any]()
        
        if let authCode = request.headers[ServerConstants.HTTPOAuth2AuthorizationCodeKey] {
            result[ServerConstants.HTTPOAuth2AuthorizationCodeKey] = authCode
        }
        
        if let idToken = request.headers[ServerConstants.HTTPOAuth2AccessTokenKey] {
            result[ServerConstants.HTTPOAuth2AccessTokenKey] = idToken
        }
        
        return result
    }
    
    static func fromProperties(_ properties: AccountManager.AccountProperties, user:AccountCreationUser?, delegate:AccountDelegate?) -> Account? {
        let creds = AppleSignInCreds()
        creds.accountCreationUser = user
        creds.delegate = delegate
        creds.accessToken =
            properties.properties[ServerConstants.HTTPOAuth2AccessTokenKey] as? String
        creds.serverAuthCode =
            properties.properties[ServerConstants.HTTPOAuth2AuthorizationCodeKey] as? String
        return creds
    }
    
    func toJSON() -> String? {
        let databaseCreds = DatabaseCreds(serverAuthCode: serverAuthCode, idToken: accessToken, refreshToken: refreshToken, lastRefreshTokenUsage: lastRefreshTokenUsage)
        
        let encoder = JSONEncoder()
        guard let data = try? encoder.encode(databaseCreds) else {
            Log.error("Failed encoding DatabaseCreds")
            return nil
        }
        
        return String(data: data, encoding: .utf8)
    }
    
    static func fromJSON(_ json: String, user: AccountCreationUser, delegate: AccountDelegate?) throws -> Account? {
    
        guard let data = json.data(using: .utf8) else {
            return nil
        }
    
        let decoder = JSONDecoder()
        guard let databaseCreds = try? decoder.decode(DatabaseCreds.self, from: data) else {
            return nil
        }
        
        let result = AppleSignInCreds()
        result.delegate = delegate
        result.accountCreationUser = user
        
        result.serverAuthCode = databaseCreds.serverAuthCode
        result.accessToken = databaseCreds.idToken
        result.refreshToken = databaseCreds.refreshToken
        result.lastRefreshTokenUsage = databaseCreds.lastRefreshTokenUsage

        return result
    }
}
