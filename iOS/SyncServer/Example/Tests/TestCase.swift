//
//  TestCase.swift
//  SyncServer
//
//  Created by Christopher Prince on 1/31/17.
//  Copyright © 2017 CocoaPods. All rights reserved.
//

import XCTest
@testable import SyncServer
import SMCoreLib

class TestCase: XCTestCase, ServerNetworkingAuthentication {
    var authTokens = [String:String]()
    
    // This value needs to be refreshed before running these tests.
    static let accessToken:String = {
        let plist = try! PlistDictLoader(plistFileNameInBundle: Constants.serverPlistFile)
        
        if case .stringValue(let value) = try! plist.getRequired(varName: "GoogleAccessToken") {
            return value
        }
        
        XCTFail()
        return ""
    }()
    
    override func setUp() {
        super.setUp()
        ServerNetworking.session.authenticationDelegate = self
        self.authTokens = [
            ServerConstants.XTokenTypeKey: ServerConstants.AuthTokenType.GoogleToken.rawValue,
            ServerConstants.GoogleHTTPAccessTokenKey: TestCase.accessToken
        ]
    }
    
    override func tearDown() {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
        super.tearDown()
    }
    
    // MARK: ServerNetworkingAuthentication delegate methods
    func headerAuthentication(forServerNetworking: ServerNetworking) -> [String:String]? {
        return self.authTokens
    }
}

