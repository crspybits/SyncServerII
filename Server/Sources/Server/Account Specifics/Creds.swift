//
//  Google.swift
//  Server
//
//  Created by Christopher Prince on 12/22/16.
//
//

import Foundation
import Credentials
import CredentialsGoogle
import PerfectLib
import KituraNet
import SwiftyJSON

public class Creds {
    var accountType:AccountType!
    var baseURL:String?
    
    func toJSON() -> String? {
        assert(false, "Unimplemented")
        return nil
    }
    
    class func fromProfile(profile:UserProfile) -> Creds? {
        assert(false, "Unimplemented")
        return nil
    }
    
    class func fromJSON(s:String) -> Creds? {
        assert(false, "Unimplemented")
        return nil
    }
    
    // Some Creds (e.g., Google) need to generate internal tokens (a refresh token) in some circumstances (e.g., when having a serverAuthCode). If error == nil, then success will have a non-nil value.
    func generateTokens(completion:@escaping (_ success:Bool?, Swift.Error?)->()) {
    }
    
    func merge(withNewerCreds creds:Creds) {
    }
    
    enum Body {
    case string(String)
    case data(Data)
    }
    
    enum APICallResult {
    case json(JSON)
    case data(Data)
    }
    
    // Does an HTTP call to the endpoint constructed by baseURL with path, the HTTP method, and the given body parameters (if any). BaseURL is given without any http:// or https:// (https:// is used). If baseURL is nil, then self.baseURL is used-- which must not be nil in that case.
    func apiCall(method:String, baseURL:String? = nil, path:String,
        additionalHeaders: [String:String]? = nil, urlParameters:String? = nil, body:Body? = nil,
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
                Log.debug(message: "HTTP status code: \(statusCode); raw: \(statusCode.rawValue)")
                if statusCode != HTTPStatusCode.OK {
                    for header in response.headers {
                        Log.debug(message: "Header: \(header)")
                    }
                    let result = try? response.readString()
                    Log.debug(message: "Response data as string: \(result)")
                    
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
                    Log.error(message: "Failed to read Google response: \(error)")
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

extension Creds {
    static func toCreds(accountType:AccountType, fromJSON json:String) -> Creds? {
        switch accountType {
        case .Google:
            return GoogleCreds.fromJSON(s: json)
        }
    }
    
    static func toJSON(fromProfile profile:UserProfile) -> String? {
        guard let accountType = AccountType.fromSpecificCredsType(specificCreds: profile.accountSpecificCreds!) else {
            return nil
        }
        
        switch accountType {
        case .Google:
            if let creds = GoogleCreds.fromProfile(profile: profile) {
                return creds.toJSON()
            }
            else {
                return nil
            }
        }
    }
    
    class func toCreds(fromProfile profile:UserProfile) -> Creds? {
        guard let accountType = AccountType.fromSpecificCredsType(specificCreds: profile.accountSpecificCreds!) else {
            return nil
        }
        
        switch accountType {
        case .Google:
            if let creds = GoogleCreds.fromProfile(profile: profile) {
                return creds
            }
            else {
                return nil
            }
        }
    }
}

enum AccountType : String {
    case Google
    
    static func fromSpecificCredsType(specificCreds: AccountSpecificCreds) -> AccountType? {
        switch specificCreds {
        case is GoogleSpecificCreds:
            return .Google
            
        default:
            Log.error(message: "Could not convert \(specificCreds) to AccountType")
            return nil
        }
    }
}
