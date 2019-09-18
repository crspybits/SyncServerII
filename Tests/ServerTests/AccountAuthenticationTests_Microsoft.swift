import XCTest
import Kitura
import KituraNet
@testable import Server
import LoggerAPI
import CredentialsMicrosoft
import Foundation
import SyncServerShared

class AccountAuthenticationTests_Microsoft: ServerTestCase, LinuxTestable {
    let serverResponseTime:TimeInterval = 10

    // Need to use this test to get an initial refresh token for the TestCredentials. Put an id token in the TestCredentials for .microsoft1 before this.
    func testBootstrapRefreshToken() {
        let microsoftCreds = MicrosoftCreds()
        guard let test = Configuration.test else {
            XCTFail()
            return
        }
        
        let accessToken1 = test.microsoft2RevokedAccessToken.idToken
        microsoftCreds.accessToken = accessToken1
        
        let exp = expectation(description: "generate")
        microsoftCreds.generateTokens(response: nil) { error in
            XCTAssert(error == nil, "\(String(describing: error))")
            Log.info("Refresh token: \(String(describing: microsoftCreds.refreshToken))")
            exp.fulfill()
        }
        waitExpectation(timeout: 10, handler: nil)
    }
    
    func testRefreshToken() {
        guard let test = Configuration.test else {
            XCTFail()
            return
        }
        
        let microsoftCreds = MicrosoftCreds()
        microsoftCreds.refreshToken = test.microsoft2RevokedAccessToken.refreshToken
        let exp = expectation(description: "refresh")
        microsoftCreds.refresh() { error in
            XCTAssert(error == nil)
            exp.fulfill()
        }
        waitExpectation(timeout: 10, handler: nil)
    }
    
    func testGoodEndpointWithBadCredsFails() {
        let deviceUUID = Foundation.UUID().uuidString
        performServerTest(testAccount: .microsoft1) { expectation, creds in
            let headers = self.setupHeaders(testUser: .microsoft1, accessToken: "foobar", deviceUUID:deviceUUID)
            self.performRequest(route: ServerEndpoints.checkPrimaryCreds, headers: headers) { response, dict in
                Log.info("Status Code: \(response!.statusCode.rawValue)")
                XCTAssert(response!.statusCode == .unauthorized, "Did not fail on check creds request: \(response!.statusCode)")
                expectation.fulfill()
            }
        }
    }

    // Good Microsoft creds, not creds that are necessarily on the server.
    func testGoodEndpointWithGoodCredsWorks() {
        let deviceUUID = Foundation.UUID().uuidString
        
        self.performServerTest(testAccount: .microsoft1) { expectation, creds in
            let headers = self.setupHeaders(testUser: .microsoft1, accessToken: creds.accessToken, deviceUUID:deviceUUID)
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
        
        performServerTest(testAccount: .microsoft1) { expectation, dbCreds in
            let headers = self.setupHeaders(testUser: .microsoft1, accessToken: dbCreds.accessToken, deviceUUID:deviceUUID)
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
        
        self.performServerTest(testAccount: .microsoft1) { expectation, dbCreds in
            let headers = self.setupHeaders(testUser: .microsoft1, accessToken: dbCreds.accessToken, deviceUUID:deviceUUID)
            self.performRequest(route: badRoute, headers: headers) { response, dict in
                XCTAssert(response!.statusCode != .OK, "Did not fail on check creds request")
                expectation.fulfill()
            }
        }
    }
    
    func testThatMicrosoftUserHasValidCreds() {
        let deviceUUID = Foundation.UUID().uuidString
        let sharingGroupUUID = Foundation.UUID().uuidString

        addNewUser(testAccount: .microsoft1, sharingGroupUUID: sharingGroupUUID, deviceUUID:deviceUUID, cloudFolderName: nil)
        
        self.performServerTest(testAccount: .microsoft1) { expectation, dbCreds in
            let headers = self.setupHeaders(testUser: .microsoft1, accessToken: dbCreds.accessToken, deviceUUID:deviceUUID)
            self.performRequest(route: ServerEndpoints.checkCreds, headers: headers) { response, dict in
                Log.info("Status code: \(response!.statusCode)")
                XCTAssert(response!.statusCode == .OK, "Did not work on check creds request")
                expectation.fulfill()
            }
        }
    }
}

extension AccountAuthenticationTests_Microsoft {
    static var allTests : [(String, (AccountAuthenticationTests_Microsoft) -> () throws -> Void)] {
        let result:[(String, (AccountAuthenticationTests_Microsoft) -> () throws -> Void)] = [
            ("testBootstrapRefreshToken", testBootstrapRefreshToken),
            ("testRefreshToken", testRefreshToken),
            ("testGoodEndpointWithBadCredsFails", testGoodEndpointWithBadCredsFails),
            ("testGoodEndpointWithGoodCredsWorks", testGoodEndpointWithGoodCredsWorks),
            ("testBadPathWithGoodCredsFails", testBadPathWithGoodCredsFails),
            ("testGoodPathWithBadMethodWithGoodCredsFails", testGoodPathWithBadMethodWithGoodCredsFails),
            ("testThatMicrosoftUserHasValidCreds", testThatMicrosoftUserHasValidCreds),
            ]
        
        return result
    }
    
    func testLinuxTestSuiteIncludesAllTests() {
        linuxTestSuiteIncludesAllTests(testType:AccountAuthenticationTests_Microsoft.self)
    }
}
