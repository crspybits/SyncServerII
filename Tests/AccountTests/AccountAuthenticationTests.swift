import XCTest
import Kitura
import KituraNet
@testable import Server
@testable import TestsCommon
import LoggerAPI
import HeliumLogger
import Foundation
import ServerShared

/*
I've been trying to create parameterized test cases so I can have one shared test across the AccountAuthenticationTests for the specific types of accounts. I would like to do this by using a base class. However, there are problems. XCTest is not well supported on Linux. And getting the tests detected otherwise doesn't work on Linux.
See also
https://stackoverflow.com/questions/34928632
https://bugs.swift.org/browse/SR-12232
https://oleb.net/2020/swift-test-discovery/
*/

class AccountAuthenticationTests: ServerTestCase, LinuxTestable {
    let serverResponseTime:TimeInterval = 10
    var testAccount: TestAccount!
    var cloudFolderName:String?
    
    func testGoodEndpointWithBadCredsFails() {
        guard let testAccount = testAccount else { return }
        let deviceUUID = Foundation.UUID().uuidString
        performServerTest(testAccount: testAccount) { expectation, creds in
            let headers = self.setupHeaders(testUser: self.testAccount, accessToken: "foobar", deviceUUID:deviceUUID)
            self.performRequest(route: ServerEndpoints.checkPrimaryCreds, headers: headers) { response, dict in
                Log.info("Status Code: \(response!.statusCode.rawValue)")
                XCTAssert(response!.statusCode == .unauthorized, "Did not fail on check creds request: \(response!.statusCode)")
                expectation.fulfill()
            }
        }
    }

    // Good creds, not creds that are necessarily on the server.
    func testGoodEndpointWithGoodCredsWorks() {
        guard let testAccount = testAccount else { return }
        let deviceUUID = Foundation.UUID().uuidString
        
        self.performServerTest(testAccount: testAccount) { expectation, creds in
            let headers = self.setupHeaders(testUser: self.testAccount, accessToken: creds.accessToken, deviceUUID:deviceUUID)
            self.performRequest(route: ServerEndpoints.checkPrimaryCreds, headers: headers) { response, dict in
                Log.info("Status code: \(response!.statusCode)")
                XCTAssert(response!.statusCode == .OK, "Did not work on check creds request")
                expectation.fulfill()
            }
        }
    }
    
    func testBadPathWithGoodCredsFails() {
        guard let testAccount = testAccount else { return }
        let badRoute = ServerEndpoint("foobar", method: .post, requestMessageType: AddUserRequest.self)
        let deviceUUID = Foundation.UUID().uuidString
        
        performServerTest(testAccount: testAccount) { expectation, dbCreds in
            let headers = self.setupHeaders(testUser: self.testAccount, accessToken: dbCreds.accessToken, deviceUUID:deviceUUID)
            self.performRequest(route: badRoute, headers: headers) { response, dict in
                XCTAssert(response!.statusCode != .OK, "Did not fail on check creds request")
                expectation.fulfill()
            }
        }
    }

    func testGoodPathWithBadMethodWithGoodCredsFails() {
        guard let testAccount = testAccount else { return }
        let badRoute = ServerEndpoint(ServerEndpoints.checkCreds.pathName, method: .post, requestMessageType: CheckCredsRequest.self)
        XCTAssert(ServerEndpoints.checkCreds.method != .post)
        let deviceUUID = Foundation.UUID().uuidString
        
        self.performServerTest(testAccount: testAccount) { expectation, dbCreds in
            let headers = self.setupHeaders(testUser: self.testAccount, accessToken: dbCreds.accessToken, deviceUUID:deviceUUID)
            self.performRequest(route: badRoute, headers: headers) { response, dict in
                XCTAssert(response!.statusCode != .OK, "Did not fail on check creds request")
                expectation.fulfill()
            }
        }
    }
    
    func testThatUserHasValidCreds() {
        guard let testAccount = testAccount else { return }
        let deviceUUID = Foundation.UUID().uuidString
        let sharingGroupUUID = Foundation.UUID().uuidString

        addNewUser(testAccount: testAccount, sharingGroupUUID: sharingGroupUUID, deviceUUID:deviceUUID, cloudFolderName: cloudFolderName)
        
        self.performServerTest(testAccount: testAccount) { expectation, dbCreds in
            let headers = self.setupHeaders(testUser: self.testAccount, accessToken: dbCreds.accessToken, deviceUUID:deviceUUID)
            self.performRequest(route: ServerEndpoints.checkCreds, headers: headers) { response, dict in
                Log.info("Status code: \(response!.statusCode)")
                XCTAssert(response!.statusCode == .OK, "Did not work on check creds request")
                expectation.fulfill()
            }
        }
    }
}

extension AccountAuthenticationTests {
    static var allTests : [(String, (AccountAuthenticationTests) -> () throws -> Void)] {
        let result:[(String, (AccountAuthenticationTests) -> () throws -> Void)] = [
            ("testGoodEndpointWithBadCredsFails", testGoodEndpointWithBadCredsFails),
            ("testGoodEndpointWithGoodCredsWorks", testGoodEndpointWithGoodCredsWorks),
            ("testBadPathWithGoodCredsFails", testBadPathWithGoodCredsFails),
            ("testGoodPathWithBadMethodWithGoodCredsFails", testGoodPathWithBadMethodWithGoodCredsFails),
            ("testThatUserHasValidCreds", testThatUserHasValidCreds),
            ]
        
        return result
    }
    
    func testLinuxTestSuiteIncludesAllTests() {
        linuxTestSuiteIncludesAllTests(testType:AccountAuthenticationTests.self)
    }
}
