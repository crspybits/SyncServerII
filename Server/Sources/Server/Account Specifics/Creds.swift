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
    
    // Does an HTTP call to the endpoint constructed by baseURL with path, the HTTP method, and the given body parameters (if any). BaseURL is given without any http:// or https:// (https:// is used). If baseURL is nil, then self.baseURL is used-- which must not be nil in that case.
    func apiCall(method:String, baseURL:String? = nil, path:String,
        additionalHeaders: [String:String]? = nil, urlParameters:String? = nil, body:Body? = nil,
        completion:@escaping (_ result: JSON?, HTTPStatusCode?)->()) {
        
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
            let escapedURLParams = urlParameters!.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed)
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
            if let response = response {
                let statusCode = response.statusCode
                Log.debug(message: "HTTP status code: \(statusCode)")
                if statusCode != HTTPStatusCode.OK {
                    completion(nil, statusCode)
                    return
                }
                
                var body = Data()
                do {
                    try response.readAllData(into: &body)
                    let jsonBody = JSON(data: body)
                    completion(jsonBody, statusCode)
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
