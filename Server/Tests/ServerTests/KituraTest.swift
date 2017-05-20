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

protocol KituraTest {
    func expectation(_ index: Int) -> XCTestExpectation
    func waitExpectation(timeout t: TimeInterval, handler: XCWaitCompletionHandler?)
}

enum ResponseDictFrom {
case body
case header
}

enum CredentialsToken : String {
case googleRefreshToken1 = "GoogleRefreshToken"
case googleSub1 = "GoogleSub"

case googleRefreshToken2 = "GoogleRefreshToken2"
case googleSub2 = "GoogleSub2"

case googleRefreshToken3 = "GoogleRefreshToken3"
case googleSub3 = "GoogleSub3"

case facebook = "FacebookLongLivedToken"
}

// TODO: *0* Why do I have to have both Server.json and ServerTests.json for testing??

extension KituraTest {
    // I've put this method here (instead of in Constants) because it is just a part of testing, not part of the full-blown server.
    func credentialsToken(token:CredentialsToken = .googleRefreshToken1) -> String {
#if os(macOS)
        let config = try! ConfigLoader(usingPath: "/tmp", andFileName: "Server.json", forConfigType: .jsonDictionary)
#else // Linux
        let config = try! ConfigLoader(usingPath: "../../Private/Server", andFileName: "Server.json", forConfigType: .jsonDictionary)
#endif
        let token = try! config.getString(varName: token.rawValue)
        return token
    }
    
    func performServerTest(token:CredentialsToken = .googleRefreshToken1,
        asyncTasks: @escaping (XCTestExpectation, GoogleCreds) -> Void...) {
        
        let creds = GoogleCreds()
        creds.refreshToken = self.credentialsToken(token:token)
        creds.refresh { error in
            XCTAssert(error == nil)
            
            ServerMain.startup(type: .nonBlocking)
            
            let requestQueue = DispatchQueue(label: "Request queue")

            for (index, asyncTask) in asyncTasks.enumerated() {
                let expectation = self.expectation(index)
                requestQueue.async() {
                    asyncTask(expectation, creds)
                }
            }

            // blocks test until request completes
            self.waitExpectation(timeout: 60) { error in
                ServerMain.shutdown()
                XCTAssertNil(error)
            }
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
        let options: [ClientRequest.Options] =
            [.disableSSLVerification, .schema("https://"), .method(route.method.rawValue), .hostname("localhost"),
                .port(Int16(ServerMain.port)), .path(path), .headers(allHeaders)]
        
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
    
    func setupHeaders(accessToken: String, deviceUUID:String) -> [String: String] {
        var headers = [String: String]()
        headers[CredentialsGoogleToken.xTokenTypeKey] = ServerConstants.AuthTokenType.GoogleToken.rawValue
        headers[CredentialsGoogleToken.accessTokenKey] = accessToken
        headers[ServerConstants.httpRequestDeviceUUID] = deviceUUID
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

