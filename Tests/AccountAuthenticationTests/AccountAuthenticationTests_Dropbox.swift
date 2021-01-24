import XCTest
import Kitura
import KituraNet
@testable import Server
@testable import TestsCommon
import LoggerAPI
import HeliumLogger
import CredentialsDropbox
import Foundation
import ServerShared

class AccountAuthenticationTests_Dropbox: AccountAuthenticationTests {
    override func setUp() {
        super.setUp()
        testAccount = .dropbox1
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

