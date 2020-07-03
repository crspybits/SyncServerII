//
//  AccountAuthenticationTests_Facebook.swift
//  ServerTests
//
//  Created by Christopher Prince on 7/19/17.
//

import XCTest
import ServerShared
import LoggerAPI
@testable import Server
@testable import TestsCommon

class AccountAuthenticationTests_Facebook: AccountAuthenticationTests {
    override func setUp() {
        super.setUp()
        testAccount = .facebook1
    }
    
    override func tearDown() {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
        super.tearDown()
    }

    override func testGoodEndpointWithBadCredsFails() {
        super.testGoodEndpointWithBadCredsFails()
    }

    override func testGoodEndpointWithGoodCredsWorks() {
        super.testGoodEndpointWithGoodCredsWorks()
    }

    override func testBadPathWithGoodCredsFails() {
        super.testBadPathWithGoodCredsFails()
    }

    override func testGoodPathWithBadMethodWithGoodCredsFails() {
        super.testGoodPathWithBadMethodWithGoodCredsFails()
    }

    func testThatFacebookUserHasValidCreds() {
        createSharingUser(withSharingPermission: .read, sharingUser: .facebook1)
        
        let deviceUUID = Foundation.UUID().uuidString
        
        self.performServerTest(testAccount: .facebook1) { expectation, facebookCreds in
            let headers = self.setupHeaders(testUser: .facebook1, accessToken: facebookCreds.accessToken, deviceUUID:deviceUUID)
            self.performRequest(route: ServerEndpoints.checkCreds, headers: headers) { response, dict in
                Log.info("Status code: \(response!.statusCode)")
                XCTAssert(response!.statusCode == .OK, "Did not work on check creds request")
                expectation.fulfill()
            }
        }
    }
}

