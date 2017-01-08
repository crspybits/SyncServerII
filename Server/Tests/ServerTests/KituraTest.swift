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

protocol KituraTest {
    func expectation(_ index: Int) -> XCTestExpectation
    func waitExpectation(timeout t: TimeInterval, handler: XCWaitCompletionHandler?)
}

extension KituraTest {
    func accessToken() -> String {
        return "ya29.Ci_MA-INb3DA-ojBtk9PkDDZcXUMYf9TuBd9gCE5U9JggAbCYqrmvGyVDXYn3mbMgg"
    }
    
    func refreshToken() -> String {
        return "1/gLgz7_uYCEmvPYVgZQgGGme_iRa9Wm23ozsTvVtjVQSop59mB5ng33UbZOf2Dcyh"
    }
    
    func performServerTest(asyncTasks: @escaping (XCTestExpectation) -> Void...) {
        ServerMain.startup(type: .nonBlocking)
        
        let requestQueue = DispatchQueue(label: "Request queue")

        for (index, asyncTask) in asyncTasks.enumerated() {
            let expectation = self.expectation(index)
            requestQueue.async() {
                asyncTask(expectation)
            }
        }

        // blocks test until request completes
        waitExpectation(timeout: 30) { error in
            ServerMain.shutdown()
            XCTAssertNil(error)
        }
    }

    func performRequest(route:ServerEndpoint, headers: [String: String]? = nil, urlParameters:String? = nil, callback: @escaping (ClientResponse?, [String:Any]?) -> Void) {
    
        var allHeaders = [String: String]()
        if  let headers = headers  {
            for  (headerName, headerValue) in headers  {
                allHeaders[headerName] = headerValue
            }
        }
        
        var path = route.path
        if urlParameters != nil {
            path += "/" + urlParameters!
        }
        
        allHeaders["Content-Type"] = "text/plain"
        let options: [ClientRequest.Options] =
            [.method(route.method.rawValue), .hostname("localhost"),
                .port(Int16(ServerMain.port)), .path(path), .headers(allHeaders)]
        
        let req = HTTP.request(options) { response in
            var dict:[String:Any]?
            if response != nil {
                dict = self.getResponseDict(response: response!)
            }
            Log.info("Result: \(dict)")
            callback(response, dict)
        }
        
        req.end()
    }
    
    func getResponseDict(response:ClientResponse) -> [String: Any]? {
        var result:String?
        do {
            result = try response.readString()
        } catch (let error) {
            Log.error("Failed with error \(error)")
            return nil
        }
        
        Log.info("Result string: \(result)")
        guard let jsonString = result else {
            Log.error("Empty string obtained")
            return nil
        }
        
        if let data = jsonString.data(using: .utf8) {
            do {
                return try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any]
            } catch (let error) {
                Log.error("Failed parsing json with error \(error)")
                return nil
            }
        }
        
        return nil
    }
    
    func setupHeaders(accessToken: String) -> [String: String] {
        var headers = [String: String]()
        headers[CredentialsGoogleToken.xTokenTypeKey] = ServerConstants.AuthTokenType.GoogleToken.rawValue
        headers[CredentialsGoogleToken.accessTokenKey] = accessToken
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

