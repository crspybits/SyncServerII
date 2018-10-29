//
//  Account.swift
//  Server
//
//  Created by Christopher Prince on 7/9/17.
//

import Foundation
import SyncServerShared
import Credentials
import KituraNet
import LoggerAPI
import Kitura

enum AccountCreationUser {
    case user(User) // use this if we have it.
    case userId(UserId, UserType) // and this if we don't.
}

// SyncServer specific Keys for UserProfile extendedProperties
let SyncServerAccountType = "syncServerAccountType" // In Dictionary as a String

protocol AccountDelegate : class {
    // This is delegated because (a) it enables me to only sometimes allow an Account to save to the database, and (b) because knowledge of how to save to a database seems outside of the responsibilities of `Account`s. Returns false iff an error occurred on database save.
    func saveToDatabase(account:Account) -> Bool
}

protocol Account {
    static var accountType:AccountType {get}
    var accountType:AccountType {get}
    
    // Sharing always need to return false.
    // Owning accounts return true iff they need a cloud folder name (e.g., Google Drive).
    var owningAccountsNeedCloudFolderName: Bool {get}
    
    var delegate:AccountDelegate? {get set}
    
    var accountCreationUser:AccountCreationUser? {get set}
    
    // Currently assuming all Account's use access tokens.
    var accessToken: String! {get set}
    
    func toJSON(userType: UserType) -> String?
    
    // Given existing Account info stored in the database, decide if we need to generate tokens. Token generation can be used for various purposes by the particular Account. E.g., For owning users to allow access to cloud storage data in offline manner. E.g., to allow access that data by sharing users.
    func needToGenerateTokens(userType:UserType, dbCreds:Account?) -> Bool
    
    // Some Account's (e.g., Google) need to generate internal tokens (e.g., a refresh token) in some circumstances (e.g., when having a serverAuthCode). May use delegate, if one is defined, to save creds to database. Some accounts may use HTTP header in RouterResponse to send back token(s).
    func generateTokens(response: RouterResponse, completion:@escaping (Swift.Error?)->())
    
    func merge(withNewer account:Account)
    
    // Only updates the user profile if the request header has the Account's specific token.
    static func updateUserProfile(_ userProfile:UserProfile, fromRequest request:RouterRequest)
    
    static func fromProfile(profile:UserProfile, user:AccountCreationUser?, delegate:AccountDelegate?) -> Account?
    static func fromJSON(_ json:String, user:AccountCreationUser, delegate:AccountDelegate?) throws -> Account?
}

enum FromJSONError : Swift.Error {
    case noRequiredKeyValue
}

extension Account {    
    // Only use this for owning accounts.
    var cloudFolderName: String? {
        guard let accountCreationUser = accountCreationUser,
            case .user(let user) = accountCreationUser,
            let cloudFolderName = user.cloudFolderName else {
            
            if owningAccountsNeedCloudFolderName {
                Log.error("Account needs cloud folder name, but has none.")
                assert(false)
            }

            return nil
        }
        
        assert(owningAccountsNeedCloudFolderName)
        return cloudFolderName
    }
    
    func generateTokensIfNeeded(userType:UserType, dbCreds:Account?, routerResponse:RouterResponse, success:@escaping ()->(), failure: @escaping ()->()) {
    
        if needToGenerateTokens(userType: userType, dbCreds: dbCreds) {
            generateTokens(response: routerResponse) { error in
                if error == nil {
                    success()
                }
                else {
                    Log.error("Failed attempting to generate tokens: \(error!))")
                    failure()
                }
            }
        }
        else {
            success()
        }
    }
    
    static func setProperty(jsonDict: [String:Any], key:String, required:Bool=true, setWithValue:(String)->()) throws {
        guard let keyValue = jsonDict[key] as? String else {
            if required {
                Log.error("No \(key) value present.")
                throw FromJSONError.noRequiredKeyValue
            }
            else {
                Log.warning("No \(key) value present.")
            }
            return
        }

        setWithValue(keyValue)
    }
}

enum AccountType : String {
    case Google
    case Facebook
    case Dropbox
    
    static func `for`(userProfile:UserProfile) -> AccountType? {
        guard let accountTypeString = userProfile.extendedProperties[SyncServerAccountType] as? String else {
            return nil
        }
        
        return AccountType(rawValue: accountTypeString)
    }
    
    var userType: UserType {
        switch self {
        case .Google:
            return .owning
        case .Facebook:
            return .sharing
        case .Dropbox:
            return .owning
        }
    }
    
    var cloudStorageType: CloudStorageType? {
        switch self {
        case .Google:
            return .Google
        case .Dropbox:
            return .Dropbox
        case .Facebook:
            return nil
        }
    }
    
    func toAuthTokenType() -> ServerConstants.AuthTokenType {
        switch self {
            case .Google:
                return .GoogleToken
            case .Facebook:
                return .FacebookToken
            case .Dropbox:
                return .DropboxToken
        }
    }
    
    static func fromAuthTokenType(_ authTokenType: ServerConstants.AuthTokenType) -> AccountType {
        switch authTokenType {
            case .GoogleToken:
                return .Google
            case .FacebookToken:
                return .Facebook
            case .DropboxToken:
                return .Dropbox
        }
    }
}

enum APICallBody {
    case string(String)
    case data(Data)
}

enum APICallResult {
    case dictionary([String: Any])
    case array([Any])
    case data(Data)
}

enum GenerateTokensError : Swift.Error {
    case badStatusCode(HTTPStatusCode?)
    case couldNotObtainParameterFromJSON
    case nilAPIResult
    case errorSavingCredsToDatabase
}

// I didn't just use a protocol extension for this because I want to be able to override `apiCall` and call "super to get the base definition.
class AccountAPICall {
    // Used by `apiCall` function to make a REST call to an Account service.
    var baseURL:String?
    
    // Does an HTTP call to the endpoint constructed by baseURL with path, the HTTP method, and the given body parameters (if any). BaseURL is given without any http:// or https:// (https:// is used). If baseURL is nil, then self.baseURL is used-- which must not be nil in that case.
    // expectingData == true means return Data. false or nil just look for Data or JSON result.
    func apiCall(method:String, baseURL:String? = nil, path:String,
                 additionalHeaders: [String:String]? = nil, urlParameters:String? = nil,
                 body:APICallBody? = nil,
                 returnResultWhenNon200Code:Bool = false,
                 expectingData:Bool? = nil,
        completion:@escaping (_ result: APICallResult?, HTTPStatusCode?, _ responseHeaders: HeadersContainer?)->()) {
        
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
                    
                    if !returnResultWhenNon200Code {
                        completion(nil, statusCode, nil)
                        return
                    }
                }
                
                var body = Data()
                do {
                    try response.readAllData(into: &body)
                    var result:APICallResult?

                    if let expectingData = expectingData, expectingData {
                        result = .data(body)
                    }
                    else {
                        let jsonResult:Any = try JSONSerialization.jsonObject(with: body, options: [])
                        
                        if let dictionary = jsonResult as? [String : Any] {
                            result = .dictionary(dictionary)
                        }
                        else if let array = jsonResult as? [Any] {
                            result = .array(array)
                        }
                        else {
                            result = .data(body)
                        }
                    }
                    
                    completion(result, statusCode, response.headers)
                    return
                } catch (let error) {
                    Log.error("Failed to read response: \(error)")
                }
            }
            
            completion(nil, nil, nil)
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

