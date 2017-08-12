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
    
    static var accountType:AccountType {
        return .Facebook
    }

    weak var delegate:AccountDelegate?
    
    var accountCreationUser:AccountCreationUser?
    
    static var signInType:SignInType {
        return .sharingUser
    }
    
    override init() {
        super.init()
        baseURL = "graph.facebook.com"
    }
    
    // There is no need to put any tokens into the database for Facebook. We don't need to access Facebook creds when the mobile user is offline, and this would just make an extra security issue.
    func toJSON(userType: UserType) -> String? {
        let jsonDict = [String:String]()
        return JSONExtras.toJSONString(dict: jsonDict)
    }
    
    // We're using token generation with Facebook to exchange a short-lived access token for a long-lived one. See https://developers.facebook.com/docs/facebook-login/access-tokens/expiration-and-extension and https://stackoverflow.com/questions/37674620/do-facebook-has-a-refresh-token-of-oauth/37683233
    func needToGenerateTokens(userType:UserType, dbCreds:Account? = nil) -> Bool {
        assert(userType == .sharing)
        return true
    }

    enum GenerateTokensError : Swift.Error {
        case non200ErrorCode(Int?)
        case didNotReceiveJSON
        case noAccessTokenInResult
    }
    
    func generateTokens(response: RouterResponse, completion:@escaping (Swift.Error?)->())  {
        let fbAppId = Constants.session.facebookClientId!
        let fbAppSecret = Constants.session.facebookClientSecret!
        
        let urlParameters = "grant_type=fb_exchange_token&client_id=\(fbAppId)&client_secret=\(fbAppSecret)&fb_exchange_token=\(accessToken!)"

        /*
        GET /oauth/access_token?
         grant_type=fb_exchange_token&amp;
         client_id={app-id}&amp;
         client_secret={app-secret}&amp;
         fb_exchange_token={short-lived-token}
        */
        
        apiCall(method: "GET", path: "/oauth/access_token",
                urlParameters: urlParameters) { apiCallResult, httpStatus in
            if httpStatus == HTTPStatusCode.OK {
                switch apiCallResult {
                case .some(.json(let json)):
                    guard let jsonAccessToken = json.dictionary?["access_token"],
                        let accessToken = jsonAccessToken.string else {
                        completion(GenerateTokensError.noAccessTokenInResult)
                        return
                    }
                    
                    response.headers[ServerConstants.httpResponseOAuth2AccessTokenKey] = accessToken
                    completion(nil)
                    
                default:
                    completion(GenerateTokensError.didNotReceiveJSON)
                }
            }
            else {
                completion(GenerateTokensError.non200ErrorCode(httpStatus.map { $0.rawValue }))
            }
        }
    }
    
    func merge(withNewer account:Account) {
    }
    
    // Only updates the user profile if the request header has the Account's specific token.
    static func updateUserProfile(_ userProfile:UserProfile, fromRequest request:RouterRequest) {
        userProfile.extendedProperties[ServerConstants.HTTPOAuth2AccessTokenKey] = request.headers[ServerConstants.HTTPOAuth2AccessTokenKey]
    }
    
    static func fromProfile(profile:UserProfile, user:AccountCreationUser?, delegate:AccountDelegate?) -> Account? {
        
        let creds = FacebookCreds()
        creds.accountCreationUser = user
        creds.delegate = delegate
        creds.accessToken = profile.extendedProperties[ServerConstants.HTTPOAuth2AccessTokenKey] as? String
        return creds
    }
    
    static func fromJSON(_ json:String, user:AccountCreationUser?, delegate:AccountDelegate?) throws -> Account? {
        
        let creds = FacebookCreds()
        creds.accountCreationUser = user
        creds.delegate = delegate
        
        return creds
    }
}

