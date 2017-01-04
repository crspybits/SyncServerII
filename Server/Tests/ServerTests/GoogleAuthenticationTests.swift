import XCTest
import Kitura
import KituraNet
@testable import Server
import LoggerAPI
import CredentialsGoogle

class GoogleAuthenticationTests: XCTestCase {    
    let serverResponseTime:TimeInterval = 10

    func testGoodEndpointWithBadCredsFails() {
        performServerTest { expectation in
            let headers = self.setupHeaders(accessToken: "foobar")
            self.performRequest(route: ServerEndpoints.checkCreds, headers: headers) { response, dict in
                Log.info("Status code: \(response!.statusCode)")
                XCTAssert(response!.statusCode != .OK, "Did not fail on check creds request")
                expectation.fulfill()
            }
        }
    }

    // Good Google creds, not creds that are necessarily on the server.
    func testGoodEndpointWithGoodCredsWorks() {
        performServerTest { expectation in
            let headers = self.setupHeaders(accessToken: self.accessToken())
            self.performRequest(route: ServerEndpoints.checkPrimaryCreds, headers: headers) { response, dict in
                Log.info("Status code: \(response!.statusCode)")
                XCTAssert(response!.statusCode == .OK, "Did not work on check creds request")
                expectation.fulfill()
            }
        }
    }
    
    func testBadPathWithGoodCredsFails() {
        let badRoute = ServerEndpoint("foobar", method: .post)

        performServerTest { expectation in
            let headers = self.setupHeaders(accessToken: self.accessToken())
            self.performRequest(route: badRoute, headers: headers) { response, dict in
                XCTAssert(response!.statusCode != .OK, "Did not fail on check creds request")
                expectation.fulfill()
            }
        }
    }

    func testGoodPathWithBadMethodWithGoodCredsFails() {
        let badRoute = ServerEndpoint(ServerEndpoints.checkCreds.pathName, method: .post)
        XCTAssert(ServerEndpoints.checkCreds.method != .post)
        
        performServerTest { expectation in
            let headers = self.setupHeaders(accessToken: self.accessToken())
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

