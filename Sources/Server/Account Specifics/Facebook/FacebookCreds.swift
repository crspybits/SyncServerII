//
//  FacebookCreds.swift
//  Server
//
//  Created by Christopher Prince on 7/16/17.
//

import Foundation
import SyncServerShared
import Credentials
import Kitura
import LoggerAPI
import KituraNet

class FacebookCreds : AccountAPICall,  Account {
    var accessToken: String!
    
    static var accountScheme:AccountScheme {
        return .facebook
    }
    
    var accountScheme:AccountScheme {
        return FacebookCreds.accountScheme
    }
    
    var owningAccountsNeedCloudFolderName: Bool {
        return false
    }

    weak var delegate:AccountDelegate?
    
    var accountCreationUser:AccountCreationUser?
    
    override init?() {
        super.init()
        baseURL = "graph.facebook.com"
    }
    
    // There is no need to put any tokens into the database for Facebook. We don't need to access Facebook creds when the mobile user is offline, and this would just make an extra security issue.
    func toJSON() -> String? {
        let jsonDict = [String:String]()
        return JSONExtras.toJSONString(dict: jsonDict)
    }
    
    // We're using token generation with Facebook to exchange a short-lived access token for a long-lived one. See https://developers.facebook.com/docs/facebook-login/access-tokens/expiration-and-extension and https://stackoverflow.com/questions/37674620/do-facebook-has-a-refresh-token-of-oauth/37683233
    func needToGenerateTokens(dbCreds:Account? = nil) -> Bool {    
        // 11/5/17; See SharingAccountsController.swift comment with the same date for the reason for this conditional compilation. When running the server XCTest cases, make sure to turn on this flag.
#if DEVTESTING
        return false
#else
        return true
#endif
    }

    enum GenerateTokensError : Swift.Error {
        case non200ErrorCode(Int?)
        case didNotReceiveJSON
        case noAccessTokenInResult
        case noAppIdOrSecret
    }
    
    func generateTokens(response: RouterResponse?, completion:@escaping (Swift.Error?)->())  {
        guard let fbAppId = Configuration.server.FacebookClientId,
            let fbAppSecret = Configuration.server.FacebookClientSecret else {
            completion(GenerateTokensError.noAppIdOrSecret)
            return
        }
        
        let urlParameters = "grant_type=fb_exchange_token&client_id=\(fbAppId)&client_secret=\(fbAppSecret)&fb_exchange_token=\(accessToken!)"

        Log.debug("urlParameters: \(urlParameters)")
        /*
        GET /oauth/access_token?
         grant_type=fb_exchange_token&amp;
         client_id={app-id}&amp;
         client_secret={app-secret}&amp;
         fb_exchange_token={short-lived-token}
        */
        
        apiCall(method: "GET", path: "/oauth/access_token",
                urlParameters: urlParameters) { apiCallResult, httpStatus, responseHeaders in
            if httpStatus == HTTPStatusCode.OK {
                switch apiCallResult {
                case .some(.dictionary(let dictionary)):
                    guard let accessToken = dictionary["access_token"] as? String else {
                        completion(GenerateTokensError.noAccessTokenInResult)
                        return
                    }
                    
                    response?.headers[ServerConstants.httpResponseOAuth2AccessTokenKey] = accessToken
                    completion(nil)
                    
                default:
                    completion(GenerateTokensError.didNotReceiveJSON)
                }
            }
            else {
                Log.debug("apiCallResult: \(String(describing: apiCallResult))")
                completion(GenerateTokensError.non200ErrorCode(httpStatus.map { $0.rawValue }))
            }
        }
    }
    
    func merge(withNewer account:Account) {
    }
    
    static func getProperties(fromRequest request:RouterRequest) -> [String: Any] {
        if let accessToken = request.headers[ServerConstants.HTTPOAuth2AccessTokenKey] {
            return [ServerConstants.HTTPOAuth2AccessTokenKey: accessToken]
        } else {
            return [:]
        }
    }
    
    static func fromProperties(_ properties: AccountManager.AccountProperties, user:AccountCreationUser?, delegate:AccountDelegate?) -> Account? {
        guard let creds = FacebookCreds() else {
            return nil
        }
        
        creds.accountCreationUser = user
        creds.delegate = delegate
        creds.accessToken = properties.properties[ServerConstants.HTTPOAuth2AccessTokenKey] as? String
        return creds
    }
    
    static func fromJSON(_ json:String, user:AccountCreationUser, delegate:AccountDelegate?) throws -> Account? {
        
        guard let creds = FacebookCreds() else {
            return nil
        }
        
        creds.accountCreationUser = user
        creds.delegate = delegate
        
        return creds
    }
}

