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

// For general strategy used with Apple Sign In-- see
// https://stackoverflow.com/questions/58178187
// https://github.com/crspybits/CredentialsAppleSignIn and
// https://forums.developer.apple.com/message/386237

class AppleSignInCreds: AccountAPICall, Account {
    enum AppleSignInCredsError: Swift.Error {
        case noCallToNeedToGenerateTokens
        case failedCreatingClientSecret
    }
    
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
        
        // Because Apple imposes limits about how often you can validate the refresh token.
        let lastRefreshTokenValidation: Date?
    }
    
    var accessToken: String!
    private var serverAuthCode:String?
    
    // Obtained via the serverAuthCode
    var refreshToken: String?
    
    var lastRefreshTokenValidation: Date?
    
    enum GenerateTokens {
        case noGeneration
        case generateRefreshToken(serverAuthCode: String)
        case refreshIdTokenUsingRefreshToken(refreshToken: String)
        
        // Apple says we can't refresh tokens more than once per day.
        static let minimumRefreshDuration: TimeInterval = 60 * 60 * 24
        
        static func needToRefreshIdToken(lastRefreshTokenUsage: Date) -> Bool {
            let timeIntervalSinceLastRefresh = Date().timeIntervalSince(lastRefreshTokenUsage)
            return timeIntervalSinceLastRefresh >= minimumRefreshDuration
        }
    }
    
    private var generateTokens: GenerateTokens?
    let config: ServerConfiguration.AppleSignIn
    
    override init?() {
        guard let config = Configuration.server.appleSignIn else {
            return nil
        }
        
        self.config = config
        super.init()
        baseURL = "appleid.apple.com"
    }
    
    func needToGenerateTokens(dbCreds: Account?) -> Bool {
        // Since a) presumably we can't use a serverAuthCode more than once, and b) Apple throttles use of the refresh token, don't generate tokens unless we have a delegate to save the tokens.
        guard let _ = delegate else {
            return false
        }

        if let dbCreds = dbCreds {
            guard dbCreds is AppleSignInCreds else {
                Log.error("dbCreds were not AppleSignInCreds")
                return false
            }
        }
        
        // The tokens in `self` are assumed to be from the request headers -- i.e., they are new.
        
        // Do we have a new server auth code? If so, then this is our first priority. Because subsequent id tokens will be generated from the refresh token created from the server auth code?
        if let requestServerAuthCode = serverAuthCode {
            if let dbCreds = dbCreds as? AppleSignInCreds,
                let databaseServerAuthCode = dbCreds.serverAuthCode {
                if databaseServerAuthCode != requestServerAuthCode {
                    generateTokens = .generateRefreshToken(serverAuthCode: requestServerAuthCode)
                    return true
                }
            }
            else {
                // We don't have an existing server auth code; assume this means this is a new user.
                generateTokens = .generateRefreshToken(serverAuthCode: requestServerAuthCode)
                return true
            }
        }
        // Don't need to check the case where only the db creds have a server auth code because if we stored the server auth code in the database, we used it already.
        
        // Not using a new server auth code. Is it time to generate a new id token?
        var lastRefresh: Date?
        var refreshToken = ""
        
        if let dbCreds = dbCreds as? AppleSignInCreds,
            let last = dbCreds.lastRefreshTokenValidation,
            let token = dbCreds.refreshToken {
            lastRefresh = last
            refreshToken = token
        }
        else if let _ = lastRefreshTokenValidation, let token = self.refreshToken {
            lastRefresh = lastRefreshTokenValidation
            refreshToken = token
        }
        
        if let last = lastRefresh,
            GenerateTokens.needToRefreshIdToken(lastRefreshTokenUsage: last) {
            generateTokens = .refreshIdTokenUsingRefreshToken(refreshToken: refreshToken)
            return true
        }
        
        generateTokens = .noGeneration
        return false
    }
    
    func generateTokens(response: RouterResponse?, completion: @escaping (Error?) -> ()) {
        guard let generateTokens = generateTokens else {
            completion(AppleSignInCredsError.noCallToNeedToGenerateTokens)
            return
        }
        
        switch generateTokens {
        case .noGeneration:
            self.generateTokens = nil
            completion(nil)
            
        case .generateRefreshToken(serverAuthCode: let serverAuthCode):
            break
            
        case .refreshIdTokenUsingRefreshToken(refreshToken: let refreshToken):
            break
        }
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
        guard let creds = AppleSignInCreds() else {
            return nil
        }
        
        creds.accountCreationUser = user
        creds.delegate = delegate
        creds.accessToken =
            properties.properties[ServerConstants.HTTPOAuth2AccessTokenKey] as? String
        creds.serverAuthCode =
            properties.properties[ServerConstants.HTTPOAuth2AuthorizationCodeKey] as? String
        return creds
    }
    
    func toJSON() -> String? {
        let databaseCreds = DatabaseCreds(serverAuthCode: serverAuthCode, idToken: accessToken, refreshToken: refreshToken, lastRefreshTokenValidation: lastRefreshTokenValidation)
        
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
        
        guard let result = AppleSignInCreds() else {
            return nil
        }
        
        result.delegate = delegate
        result.accountCreationUser = user
        
        result.serverAuthCode = databaseCreds.serverAuthCode
        result.accessToken = databaseCreds.idToken
        result.refreshToken = databaseCreds.refreshToken
        result.lastRefreshTokenValidation = databaseCreds.lastRefreshTokenValidation

        return result
    }
}
