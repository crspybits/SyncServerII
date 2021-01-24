import XCTest
import Kitura
import KituraNet
@testable import Server
@testable import TestsCommon
import LoggerAPI
import CredentialsGoogle
import Foundation
import ServerShared
@testable import ServerGoogleAccount

class AccountAuthenticationTests_Google: AccountAuthenticationTests {
    override func setUp() {
        super.setUp()
        testAccount = .google1
        cloudFolderName = "Test.Folder"
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
    
    override func testThatAccountForExistingUserCannotBeCreated() {
        super.testThatAccountForExistingUserCannotBeCreated()
    }
}
