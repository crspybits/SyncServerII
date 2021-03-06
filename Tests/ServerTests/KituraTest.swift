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
import SyncServerShared

protocol KituraTest {
    func expectation(_ index: Int) -> XCTestExpectation
    func waitExpectation(timeout t: TimeInterval, handler: XCWaitCompletionHandler?)
}

enum ResponseDictFrom {
case body
case header
}

extension KituraTest {
    func performServerTest(testAccount:TestAccount = .primaryOwningAccount,
        asyncTask: @escaping (XCTestExpectation, Account) -> Void) {
        
        func runTest(usingCreds creds:Account) {
            Log.info("performServerTest: Starts")
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
            
            // At least with Google accounts, I'm having problems with periodic `unauthorized` responses. Could be due to some form of throttling?
            if testAccount.scheme.accountName == AccountScheme.google.accountName {
                sleep(5)
            }
            Log.info("performServerTest: Ends")
        }
        
        testAccount.scheme.doHandler(for: .getCredentials, testAccount: testAccount) { creds in
            runTest(usingCreds: creds)
        }
    }
    
    // Perform server test, with no creds. e.g., health check.
    func performServerTest(asyncTask: @escaping (XCTestExpectation) -> Void) {
        Log.info("performServerTest: Starts")
        ServerMain.startup(type: .nonBlocking)
        
        let requestQueue = DispatchQueue(label: "Request queue")
        let expectation = self.expectation(0)
        requestQueue.async() {
            asyncTask(expectation)
        }

        // blocks test until request completes
        self.waitExpectation(timeout: 60) { error in
            ServerMain.shutdown()
            XCTAssertNil(error)
        }
        Log.info("performServerTest: Ends")
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
        
        let options: [ClientRequest.Options] =
            [.method(route.method.rawValue), .hostname("localhost"),
                .port(Int16(Configuration.server.port)), .path(path), .headers(allHeaders), .schema("http://")]
        
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
                Log.error("Could not obtain response parameters from header")
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
            Log.error("Could not convert string to JSON dict")
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
        
        headers[ServerConstants.XTokenTypeKey] = testUser.scheme.authTokenType
        headers[ServerConstants.HTTPOAuth2AccessTokenKey] = accessToken
        headers[ServerConstants.httpRequestDeviceUUID] = deviceUUID
        
        testUser.scheme.specificHeaderSetup(headers: &headers, testUser: testUser)

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

