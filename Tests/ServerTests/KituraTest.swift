// Modified from:

/**
 * Copyright IBM Corporation 2016
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 **/

import XCTest
import Kitura
import HeliumLogger
import KituraNet
import LoggerAPI
import Dispatch
import Foundation
@testable import Server
import CredentialsGoogle
import SMServerLib
import PerfectLib
import SyncServerShared

protocol KituraTest {
    func expectation(_ index: Int) -> XCTestExpectation
    func waitExpectation(timeout t: TimeInterval, handler: XCWaitCompletionHandler?)
}

enum ResponseDictFrom {
case body
case header
}

func ==(lhs: TestAccount, rhs:TestAccount) -> Bool {
    return lhs.tokenKey == rhs.tokenKey && lhs.idKey == rhs.idKey
}

struct TestAccount {
    // These String's are keys into a .json file.
    let tokenKey:String // key values: e.g., Google: a refresh token; Facebook:long-lived access token.
    let idKey:String
    
    let type:AccountType
    let tokenType:ServerConstants.AuthTokenType
    
    // This is the main owning account on which tests are conducted.
    static let primaryOwningAccount:TestAccount = .dropbox1
    
    static let google1 = TestAccount(tokenKey: "GoogleRefreshToken", idKey: "GoogleSub", type: .Google, tokenType: .GoogleToken)
    static let google2 = TestAccount(tokenKey: "GoogleRefreshToken2", idKey: "GoogleSub2", type: .Google, tokenType: .GoogleToken)
    static let google3 = TestAccount(tokenKey: "GoogleRefreshToken3", idKey: "GoogleSub3", type: .Google, tokenType: .GoogleToken)
    
    static func isGoogle(_ account: TestAccount) -> Bool {
        return account.type == .Google
    }
    
    static let facebook1 = TestAccount(tokenKey: "FacebookLongLivedToken1", idKey: "FacebookId1", type: .Facebook, tokenType: .FacebookToken)
    
    static let dropbox1 = TestAccount(tokenKey: "DropboxAccessToken1", idKey: "DropboxId1", type: .Dropbox, tokenType: .DropboxToken)
    
    // I've put this method here (instead of in Constants) because it is just a part of testing, not part of the full-blown server.
    private func configValue(key:String) -> String {
#if os(macOS)
        let config = try! ConfigLoader(usingPath: "/tmp", andFileName: "Server.json", forConfigType: .jsonDictionary)
#else // Linux
        let config = try! ConfigLoader(usingPath: "./", andFileName: "Server.json", forConfigType: .jsonDictionary)
#endif
        let token = try! config.getString(varName: key)
        return token
    }
    
    func token() -> String {
        return configValue(key: tokenKey)
    }
    
    func id() -> String {
        return configValue(key: idKey)
    }
}

// TODO: *0* Why do I have to have both Server.json and ServerTests.json for testing??

extension KituraTest {
    func performServerTest(testAccount:TestAccount = .primaryOwningAccount,
        asyncTask: @escaping (XCTestExpectation, Account) -> Void) {
        
        func runTest(usingCreds creds:Account) {
            ServerMain.startup(type: .nonBlocking)
            
            let requestQueue = DispatchQueue(label: "Request queue")
            let expectation = self.expectation(0)
            requestQueue.async() {
                asyncTask(expectation, creds)
            }

            // blocks test until request completes
            self.waitExpectation(timeout: 60) { error in
                ServerMain.shutdown()
                XCTAssertNil(error)
            }
        }
        
        switch testAccount.type {
        case .Google:
            let creds = GoogleCreds()
            creds.refreshToken = testAccount.token()
            creds.refresh { error in
                XCTAssert(error == nil)
                runTest(usingCreds: creds)
            }
            
        case .Facebook:
            let creds = FacebookCreds()
            creds.accessToken = testAccount.token()
            runTest(usingCreds: creds)
            
        case .Dropbox:
            let creds = DropboxCreds()
            creds.accessToken = testAccount.token()
            creds.accountId = testAccount.id()
            runTest(usingCreds: creds)
        }
    }
    
    func performRequest(route:ServerEndpoint, responseDictFrom:ResponseDictFrom = .body, headers: [String: String]? = nil, urlParameters:String? = nil, body:Data? = nil, callback: @escaping (ClientResponse?, [String:Any]?) -> Void) {
    
        var allHeaders = [String: String]()
        if  let headers = headers  {
            for  (headerName, headerValue) in headers  {
                allHeaders[headerName] = headerValue
            }
        }
        
        var path = route.pathWithSuffixSlash
        if urlParameters != nil {
            path += urlParameters!
        }
        
        allHeaders["Content-Type"] = "text/plain"
        
        var options: [ClientRequest.Options] =
            [.method(route.method.rawValue), .hostname("localhost"),
                .port(Int16(Constants.session.port)), .path(path), .headers(allHeaders)]
        
        if Constants.session.ssl.usingKituraSSL {
            // .disableSSLVerification is used here because we'll likely be using a self-signed SSL certificate for testing.
            options += [.disableSSLVerification, .schema("https://")]
        }
        else {
            options += [.schema("http://")]
        }
        
        let req:ClientRequest = HTTP.request(options) { (response:ClientResponse?) in
            var dict:[String:Any]?
            if response != nil {
                dict = self.getResponseDict(response: response!, responseDictFrom:responseDictFrom)
            }
            
            Log.info("Result: \(String(describing: dict)); \(String(describing: response))")
            callback(response, dict)
        }
        
        if body == nil {
            req.end()
        }
        else {
            req.end(body!)
        }
    }

    func getResponseDict(response:ClientResponse, responseDictFrom:ResponseDictFrom) -> [String: Any]? {
    
        var jsonString:String?

        switch responseDictFrom {
        case .body:
            do {
                jsonString = try response.readString()
            } catch (let error) {
                Log.error("Failed with error \(error)")
                return nil
            }
            
        case .header:
            guard let params = response.headers[ServerConstants.httpResponseMessageParams.lowercased()], params.count > 0 else {
                Log.error("Could not obtain parameters from header")
                return nil
            }
            
            Log.info("Result params: \(params)")
            jsonString = params[0]
        }
        
        Log.info("Result string: \(String(describing: jsonString))")
        
        guard jsonString != nil else {
            Log.error("Empty string obtained")
            return nil
        }
        
        guard let jsonDict = jsonString!.toJSONDictionary() else {
            Log.error(message: "Could not convert string to JSON dict")
            return nil
        }
        
        Log.info("Contents of dictionary:")
        for (key, value) in jsonDict {
            Log.info("key: \(key): value: \(value); type of value: \(type(of: value))")
        }
        
        return jsonDict
    }
    
    func setupHeaders(testUser: TestAccount, accessToken:String, deviceUUID:String) -> [String: String] {
        var headers = [String: String]()
        
        headers[ServerConstants.XTokenTypeKey] = testUser.tokenType.rawValue
        headers[ServerConstants.HTTPOAuth2AccessTokenKey] = accessToken
        headers[ServerConstants.httpRequestDeviceUUID] = deviceUUID
        
        if testUser.type == .Dropbox {
            headers[ServerConstants.HTTPAccountIdKey] = testUser.id()
        }

        return headers
    }
}

extension XCTestCase: KituraTest {
    func expectation(_ index: Int) -> XCTestExpectation {
        let expectationDescription = "\(type(of: self))-\(index)"
        return self.expectation(description: expectationDescription)
    }

    func waitExpectation(timeout t: TimeInterval, handler: XCWaitCompletionHandler?) {
        self.waitForExpectations(timeout: t, handler: handler)
    }
}

