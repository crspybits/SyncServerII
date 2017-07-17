//
//  Account.swift
//  Server
//
//  Created by Christopher Prince on 7/9/17.
//

import Foundation
import SyncServerShared
import Credentials
import SwiftyJSON
import KituraNet
import LoggerAPI
import Kitura

enum AccountCreationUser {
    case user(User) // use this if we have it.
    case userId(UserId) // and this if we don't.
}

// SyncServer specific Keys for UserProfile extendedProperties
let SyncServerAccountType = "syncServerAccountType" // In Dictionary as a String

protocol AccountDelegate : class {
    // This is delegated because (a) it enables me to only sometimes allow an Account to save to the database, and (b) because knowledge of how to save to a database seems outside of the responsibilities of `Account`s. Returns false iff an error occurred on database save.
    func saveToDatabase(account:Account) -> Bool
}

protocol Account {
    static var accountType:AccountType {get}
    
    weak var delegate:AccountDelegate? {get}
    
    var accountCreationUser:AccountCreationUser? {get set}
    
    func toJSON() -> String?
    
    // Given existing Account info stored in the database, decide if we need to generate tokens. The intent of generating tokens is for owning users-- to allow access to cloud storage data in offline manner. E.g., to allow access that data by sharing users.
    func needToGenerateTokens(dbCreds:Account) -> Bool
    
    // Some Account's (e.g., Google) need to generate internal tokens (a refresh token) in some circumstances (e.g., when having a serverAuthCode). If error == nil, then success will have a non-nil value. Uses delegate, if one is defined, to save creds to database.
    func generateTokens(completion:@escaping (_ success:Bool?, Swift.Error?)->())
    
    func merge(withNewer account:Account)
    
    // Only updates the user profile if the request header has the Account's specific token.
    static func updateUserProfile(_ userProfile:UserProfile, fromRequest request:RouterRequest)
    
    static func fromProfile(profile:UserProfile, user:AccountCreationUser?, delegate:AccountDelegate?) -> Account?
    static func fromJSON(_ json:String, user:AccountCreationUser?, delegate:AccountDelegate?) throws -> Account?
}

enum AccountType : String {
    case Google
    case Facebook
    
    static func `for`(userProfile:UserProfile) -> AccountType? {
        guard let accountTypeString = userProfile.extendedProperties[SyncServerAccountType] as? String else {
            return nil
        }
        
        return AccountType(rawValue: accountTypeString)
    }
    
    func toAuthTokenType() -> ServerConstants.AuthTokenType {
        switch self {
            case .Google:
                return .GoogleToken
            case .Facebook:
                return .FacebookToken
        }
    }
    
    static func fromAuthTokenType(_ authTokenType: ServerConstants.AuthTokenType) -> AccountType {
        switch authTokenType {
            case .GoogleToken:
                return .Google
            case .FacebookToken:
                return .Facebook
        }
    }
}

enum APICallBody {
    case string(String)
    case data(Data)
}

enum APICallResult {
    case json(JSON)
    case data(Data)
}

// I didn't just use a protocol extension for this because I want to be able to override `apiCall` and call "super to get the base definition.
class AccountAPICall {
    // Used by `apiCall` function to make a REST call to an Account service.
    var baseURL:String?
    
    // Does an HTTP call to the endpoint constructed by baseURL with path, the HTTP method, and the given body parameters (if any). BaseURL is given without any http:// or https:// (https:// is used). If baseURL is nil, then self.baseURL is used-- which must not be nil in that case.
    func apiCall(method:String, baseURL:String? = nil, path:String,
        additionalHeaders: [String:String]? = nil, urlParameters:String? = nil, body:APICallBody? = nil,
        completion:@escaping (_ result: APICallResult?, HTTPStatusCode?)->()) {
        
        var hostname = baseURL
        if hostname == nil {
            hostname = self.baseURL
        }
        
        var requestOptions: [ClientRequest.Options] = []
        requestOptions.append(.schema("https://"))
        requestOptions.append(.hostname(hostname!))
        requestOptions.append(.method(method))
        
        if urlParameters == nil {
            requestOptions.append(.path(path))
        }
        else {
            var charSet = CharacterSet.urlQueryAllowed
            // At least for the Google REST API, it seems single quotes need to be encoded. See https://developers.google.com/drive/v3/web/search-parameters
            // urlQueryAllowed doesn't exclude single quotes, so I'm doing that myself.
            charSet.remove("'")
            
            let escapedURLParams = urlParameters!.addingPercentEncoding(withAllowedCharacters: charSet)
            requestOptions.append(.path(path + "?" + escapedURLParams!))
        }
        
        var headers = [String:String]()
        //headers["Accept"] = "application/json; charset=UTF-8"
        headers["Accept"] = "*/*"
        
        if additionalHeaders != nil {
            for (key, value) in additionalHeaders! {
                headers[key] = value
            }
        }
        
        requestOptions.append(.headers(headers))
        
        let req = HTTP.request(requestOptions) { response in
            if let response:KituraNet.ClientResponse = response {
                let statusCode = response.statusCode
                if statusCode != HTTPStatusCode.OK {
                    // for header in response.headers {
                    //     Log.debug(message: "Header: \(header)")
                    // }
                    // let result = try? response.readString()
                    // Log.debug(message: "Response data as string: \(String(describing: result))")
                    
                    // TODO: *1* 2/26/17; I just got a non-200 result and the body of the response is: Optional("{\n \"error\": \"invalid_grant\",\n \"error_description\": \"Bad Request\"\n}\n"). My hypothesis is this that means the refresh token has expired. See also http://stackoverflow.com/questions/26724003/using-refresh-token-exception-error-invalid-grant
                    // I just created a new refresh token, and this works again. My hypothesis above seems correct on this basis.
                    // I suspect the "expiration" of the refresh token comes about here because of the method I'm using to authenticate on the client side-- I sign in again from the client, and generate a new access token, which also causes the server to generate a new refresh token (which is stored in the db, not in the Server.json file used in unit tests). And I believe there's a limit on the number of active refresh tokens.
                    // The actual `TODO` item here is to respond to the client in such a way so the client can prompt the user to re-sign in to generate an updated refresh token.
                    completion(nil, statusCode)
                    return
                }
                
                var body = Data()
                do {
                    try response.readAllData(into: &body)
                    let jsonBody = JSON(data: body)
                    var result:APICallResult?
                    
                    if jsonBody.type == .null {
                        result = .data(body)
                    }
                    else {
                        result = .json(jsonBody)
                    }
                    
                    completion(result, statusCode)
                    return
                } catch (let error) {
                    Log.error("Failed to read Google response: \(error)")
                }
            }
            
            completion(nil, nil)
        }
        
        switch body {
        case .none:
            req.end()
            
        case .some(.string(let str)):
            req.end(str)
            
        case .some(.data(let data)):
            req.end(data)
        }
    }
}

