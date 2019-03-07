//
//  AccountAuthenticationTests_Facebook.swift
//  ServerTests
//
//  Created by Christopher Prince on 7/19/17.
//

import XCTest
import SyncServerShared
import LoggerAPI
@testable import Server

class AccountAuthenticationTests_Facebook: ServerTestCase, LinuxTestable {
    
    override func setUp() {
        super.setUp()
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }
    
    override func tearDown() {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
        super.tearDown()
    }

    func testGoodEndpointWithBadCredsFails() {
        let deviceUUID = Foundation.UUID().uuidString
        performServerTest(testAccount: .facebook1) { expectation, facebookCreds in
            let headers = self.setupHeaders(testUser: .facebook1, accessToken: "foobar", deviceUUID:deviceUUID)
            self.performRequest(route: ServerEndpoints.checkPrimaryCreds, headers: headers) { response, dict in
                Log.info("Status code: \(response!.statusCode.rawValue)")
                XCTAssert(response!.statusCode == .unauthorized, "Did not fail on check creds request: \(response!.statusCode)")
                expectation.fulfill()
            }
        }
    }
    
    // Good Facebook creds, not creds that are necessarily on the server.
    func testGoodEndpointWithGoodCredsWorks() {
        let deviceUUID = Foundation.UUID().uuidString
        
        self.performServerTest(testAccount: .facebook1) { expectation, facebookCreds in
            let headers = self.setupHeaders(testUser: .facebook1, accessToken: facebookCreds.accessToken, deviceUUID:deviceUUID)
            self.performRequest(route: ServerEndpoints.checkPrimaryCreds, headers: headers) { response, dict in
                Log.info("Status code: \(response!.statusCode)")
                XCTAssert(response!.statusCode == .OK, "Did not work on check creds request")
                expectation.fulfill()
            }
        }
    }
    
    func testBadPathWithGoodCredsFails() {
        let badRoute = ServerEndpoint("foobar", method: .post, requestMessageType: AddUserRequest.self)
        let deviceUUID = Foundation.UUID().uuidString
        
        performServerTest(testAccount: .facebook1) { expectation, fbCreds in
            let headers = self.setupHeaders(testUser: .facebook1, accessToken: fbCreds.accessToken, deviceUUID:deviceUUID)
            self.performRequest(route: badRoute, headers: headers) { response, dict in
                XCTAssert(response!.statusCode != .OK, "Did not fail on check creds request")
                expectation.fulfill()
            }
        }
    }
    
    func testGoodPathWithBadMethodWithGoodCredsFails() {
        let badRoute = ServerEndpoint(ServerEndpoints.checkCreds.pathName, method: .post, requestMessageType: CheckCredsRequest.self)
        XCTAssert(ServerEndpoints.checkCreds.method != .post)
        let deviceUUID = Foundation.UUID().uuidString
        
        self.performServerTest(testAccount: .facebook1) { expectation, fbCreds in
            let headers = self.setupHeaders(testUser: .facebook1, accessToken: fbCreds.accessToken, deviceUUID:deviceUUID)
            self.performRequest(route: badRoute, headers: headers) { response, dict in
                XCTAssert(response!.statusCode != .OK, "Did not fail on check creds request")
                expectation.fulfill()
            }
        }
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

extension AccountAuthenticationTests_Facebook {
    static var allTests : [(String, (AccountAuthenticationTests_Facebook) -> () throws -> Void)] {
        let result:[(String, (AccountAuthenticationTests_Facebook) -> () throws -> Void)] = [
            ("testGoodEndpointWithBadCredsFails", testGoodEndpointWithBadCredsFails),
            ("testGoodEndpointWithGoodCredsWorks", testGoodEndpointWithGoodCredsWorks),
            ("testBadPathWithGoodCredsFails", testBadPathWithGoodCredsFails),
            ("testGoodPathWithBadMethodWithGoodCredsFails", testGoodPathWithBadMethodWithGoodCredsFails),
            ("testThatFacebookUserHasValidCreds", testThatFacebookUserHasValidCreds),
        ]
        
        return result
    }
    
    func testLinuxTestSuiteIncludesAllTests() {
        linuxTestSuiteIncludesAllTests(testType:AccountAuthenticationTests_Facebook.self)
    }
}
