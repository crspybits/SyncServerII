import XCTest
import Kitura
import KituraNet
@testable import Server
@testable import TestsCommon
import LoggerAPI
import CredentialsMicrosoft
import Foundation
import ServerShared

// These tests assume that the refresh token has been bootstrapped. We need an initial refresh token for the TestCredentials.

class AccountAuthenticationTests_Microsoft: AccountAuthenticationTests {
    override func setUp() {
        super.setUp()
        testAccount = .microsoft1
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

    override func testThatUserHasValidCreds() {
        super.testThatUserHasValidCreds()
    }

#if false
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
#endif
}


