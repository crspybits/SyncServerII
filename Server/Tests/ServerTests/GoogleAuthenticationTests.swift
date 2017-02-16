import XCTest
import Kitura
import KituraNet
@testable import Server
import LoggerAPI
import CredentialsGoogle
import PerfectLib

class GoogleAuthenticationTests: ServerTestCase {    
    let serverResponseTime:TimeInterval = 10

    func testGoodEndpointWithBadCredsFails() {
        let deviceUUID = PerfectLib.UUID().string
        performServerTest { expectation, googleCreds in
            let headers = self.setupHeaders(accessToken: "foobar", deviceUUID:deviceUUID)
            self.performRequest(route: ServerEndpoints.checkCreds, headers: headers) { response, dict in
                Log.info("Status code: \(response!.statusCode)")
                XCTAssert(response!.statusCode != .OK, "Did not fail on check creds request")
                expectation.fulfill()
            }
        }
    }

#if DEBUG
    // Good Google creds, not creds that are necessarily on the server.
    func testGoodEndpointWithGoodCredsWorks() {
        let deviceUUID = PerfectLib.UUID().string
        
        self.performServerTest { expectation, googleCreds in
            let headers = self.setupHeaders(accessToken: googleCreds.accessToken, deviceUUID:deviceUUID)
            self.performRequest(route: ServerEndpoints.checkPrimaryCreds, headers: headers) { response, dict in
                Log.info("Status code: \(response!.statusCode)")
                XCTAssert(response!.statusCode == .OK, "Did not work on check creds request")
                expectation.fulfill()
            }
        }
    }
#endif
    
    func testBadPathWithGoodCredsFails() {
        let badRoute = ServerEndpoint("foobar", method: .post)
        let deviceUUID = PerfectLib.UUID().string

        performServerTest { expectation, googleCreds in
            let headers = self.setupHeaders(accessToken: googleCreds.accessToken, deviceUUID:deviceUUID)
            self.performRequest(route: badRoute, headers: headers) { response, dict in
                XCTAssert(response!.statusCode != .OK, "Did not fail on check creds request")
                expectation.fulfill()
            }
        }
    }

    func testGoodPathWithBadMethodWithGoodCredsFails() {
        let badRoute = ServerEndpoint(ServerEndpoints.checkCreds.pathName, method: .post)
        XCTAssert(ServerEndpoints.checkCreds.method != .post)
        let deviceUUID = PerfectLib.UUID().string
            
        self.performServerTest { expectation, googleCreds in
            let headers = self.setupHeaders(accessToken: googleCreds.accessToken, deviceUUID:deviceUUID)
            self.performRequest(route: badRoute, headers: headers) { response, dict in
                XCTAssert(response!.statusCode != .OK, "Did not fail on check creds request")
                expectation.fulfill()
            }
        }
    }
    
    func testRefreshGoogleAccessTokenWorks() {
        let creds = GoogleCreds()
        creds.refreshToken = self.refreshToken()
        
        let exp = expectation(description: "\(#function)\(#line)")

        creds.refresh { error in
            XCTAssert(error == nil)
            XCTAssert(creds.accessToken != nil)
            exp.fulfill()
        }

        waitForExpectations(timeout: 10, handler: nil)
    }
}

