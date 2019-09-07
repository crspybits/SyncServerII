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
    case userId(UserId) // and this if we don't.
}

protocol AccountDelegate : class {
    // This is delegated because (a) it enables me to only sometimes allow an Account to save to the database, and (b) because knowledge of how to save to a database seems outside of the responsibilities of `Account`s. Returns false iff an error occurred on database save.
    func saveToDatabase(account:Account) -> Bool
}

protocol Account {
    static var accountScheme:AccountScheme {get}
    var accountScheme:AccountScheme {get}
    
    // Sharing always need to return false.
    // Owning accounts return true iff they need a cloud folder name (e.g., Google Drive).
    var owningAccountsNeedCloudFolderName: Bool {get}
    
    var delegate:AccountDelegate? {get set}
    
    var accountCreationUser:AccountCreationUser? {get set}
    
    // Currently assuming all Account's use access tokens.
    var accessToken: String! {get set}
    
    func toJSON() -> String?
    
    // Given existing Account info stored in the database, decide if we need to generate tokens. Token generation can be used for various purposes by the particular Account. E.g., For owning users to allow access to cloud storage data in offline manner. E.g., to allow access that data by sharing users.
    func needToGenerateTokens(dbCreds:Account?) -> Bool
    
    // Some Account's (e.g., Google) need to generate internal tokens (e.g., a refresh token) in some circumstances (e.g., when having a serverAuthCode). May use delegate, if one is defined, to save creds to database. Some accounts may use HTTP header in RouterResponse to send back token(s).
    func generateTokens(response: RouterResponse, completion:@escaping (Swift.Error?)->())
    
    func merge(withNewer account:Account)

    // Gets account specific properties, if any, from the request.
    static func getProperties(fromRequest request:RouterRequest) -> [String: Any]
    
    static func fromProperties(_ properties: AccountManager.AccountProperties, user:AccountCreationUser?, delegate:AccountDelegate?) -> Account?
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
    
    func generateTokensIfNeeded(dbCreds:Account?, routerResponse:RouterResponse, success:@escaping ()->(), failure: @escaping ()->()) {
    
        if needToGenerateTokens(dbCreds: dbCreds) {
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

extension Account {
    var cloudStorage:CloudStorage? {
#if DEBUG
        if let loadTesting = Constants.session.loadTestingCloudStorage, loadTesting {
            return MockStorage()
        }
        else {
            return self as? CloudStorage
        }
#else
        return self as? CloudStorage
#endif
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

// I didn't just use a protocol extension for this because I want to be able to override `apiCall` and call "super" to get the base definition.
class AccountAPICall {
    // Used by `apiCall` function to make a REST call to an Account service.
    var baseURL:String?
    
    private func parseResponse(_ response: ClientResponse, expectedBody: ExpectedResponse?, errorIfParsingFailure: Bool = false) -> APICallResult? {
        var result:APICallResult?

        do {
            var body = Data()
            try response.readAllData(into: &body)

            if let expectedBody = expectedBody, expectedBody == .data {
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
        } catch (let error) {
            if errorIfParsingFailure {
                Log.error("Failed to read response: \(error)")
            }
        }
        
        return result
    }
    
    enum ExpectedResponse {
        case data
        case json
    }
    
    // Does an HTTP call to the endpoint constructed by baseURL with path, the HTTP method, and the given body parameters (if any). BaseURL is given without any http:// or https:// (https:// is used). If baseURL is nil, then self.baseURL is used-- which must not be nil in that case.
    // expectingData == true means return Data. false or nil just look for Data or JSON result.
    func apiCall(method:String, baseURL:String? = nil, path:String,
                 additionalHeaders: [String:String]? = nil, urlParameters:String? = nil,
                 body:APICallBody? = nil,
                 returnResultWhenNon200Code:Bool = true,
                 expectedSuccessBody:ExpectedResponse? = nil,
                 expectedFailureBody:ExpectedResponse? = nil,
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
        
        let req = HTTP.request(requestOptions) {[unowned self] response in
            if let response:KituraNet.ClientResponse = response {
                let statusCode = response.statusCode
                
                if statusCode == HTTPStatusCode.OK {
                    if let result = self.parseResponse(response, expectedBody: expectedSuccessBody, errorIfParsingFailure: true) {
                        completion(result, statusCode, response.headers)
                        return
                    }
                }
                else {                    
                    if returnResultWhenNon200Code {
                        if let result = self.parseResponse(response, expectedBody: expectedFailureBody) {
                            completion(result, statusCode, response.headers)
                        }
                        else {
                            completion(nil, statusCode, nil)
                        }
                        return
                    }
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

