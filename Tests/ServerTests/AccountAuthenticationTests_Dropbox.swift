import XCTest
import Kitura
import KituraNet
@testable import Server
import LoggerAPI
import CredentialsDropbox
import Foundation
import SyncServerShared

class AccountAuthenticationTests_Dropbox: ServerTestCase, LinuxTestable {
    let serverResponseTime:TimeInterval = 10

    func testGoodEndpointWithBadCredsFails() {
        let deviceUUID = Foundation.UUID().uuidString
        performServerTest(testAccount: .dropbox1) { expectation, dropboxCreds in
            let headers = self.setupHeaders(testUser: .dropbox1, accessToken: "foobar", deviceUUID:deviceUUID)
            self.performRequest(route: ServerEndpoints.checkPrimaryCreds, headers: headers) { response, dict in
                Log.info("Status Code: \(response!.statusCode.rawValue)")
                XCTAssert(response!.statusCode == .unauthorized, "Did not fail on check creds request: \(response!.statusCode)")
                expectation.fulfill()
            }
        }
    }

    // Good Dropbox creds, not creds that are necessarily on the server.
    func testGoodEndpointWithGoodCredsWorks() {
        let deviceUUID = Foundation.UUID().uuidString
        
        self.performServerTest(testAccount: .dropbox1) { expectation, dropboxCreds in
            let headers = self.setupHeaders(testUser: .dropbox1, accessToken: dropboxCreds.accessToken, deviceUUID:deviceUUID)
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
        
        performServerTest(testAccount: .dropbox1) { expectation, dbCreds in
            let headers = self.setupHeaders(testUser: .dropbox1, accessToken: dbCreds.accessToken, deviceUUID:deviceUUID)
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
        
        self.performServerTest(testAccount: .dropbox1) { expectation, dbCreds in
            let headers = self.setupHeaders(testUser: .dropbox1, accessToken: dbCreds.accessToken, deviceUUID:deviceUUID)
            self.performRequest(route: badRoute, headers: headers) { response, dict in
                XCTAssert(response!.statusCode != .OK, "Did not fail on check creds request")
                expectation.fulfill()
            }
        }
    }
    
    func testThatDropboxUserHasValidCreds() {
        let deviceUUID = Foundation.UUID().uuidString
        let sharingGroupUUID = Foundation.UUID().uuidString

        addNewUser(testAccount: .dropbox1, sharingGroupUUID: sharingGroupUUID, deviceUUID:deviceUUID, cloudFolderName: nil)
        
        self.performServerTest(testAccount: .dropbox1) { expectation, dbCreds in
            let headers = self.setupHeaders(testUser: .dropbox1, accessToken: dbCreds.accessToken, deviceUUID:deviceUUID)
            self.performRequest(route: ServerEndpoints.checkCreds, headers: headers) { response, dict in
                Log.info("Status code: \(response!.statusCode)")
                XCTAssert(response!.statusCode == .OK, "Did not work on check creds request")
                expectation.fulfill()
            }
        }
    }
}

extension AccountAuthenticationTests_Dropbox {
    static var allTests : [(String, (AccountAuthenticationTests_Dropbox) -> () throws -> Void)] {
        let result:[(String, (AccountAuthenticationTests_Dropbox) -> () throws -> Void)] = [
            ("testGoodEndpointWithBadCredsFails", testGoodEndpointWithBadCredsFails),
            ("testGoodEndpointWithGoodCredsWorks", testGoodEndpointWithGoodCredsWorks),
            ("testBadPathWithGoodCredsFails", testBadPathWithGoodCredsFails),
            ("testGoodPathWithBadMethodWithGoodCredsFails", testGoodPathWithBadMethodWithGoodCredsFails),
            ("testThatDropboxUserHasValidCreds", testThatDropboxUserHasValidCreds),
            ]
        
        return result
    }
    
    func testLinuxTestSuiteIncludesAllTests() {
        linuxTestSuiteIncludesAllTests(testType:AccountAuthenticationTests_Dropbox.self)
    }
}
