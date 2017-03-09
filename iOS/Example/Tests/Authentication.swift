import XCTest
@testable import SyncServer
import SMCoreLib

// After creating this project afresh, I was getting errors like: "...couldn’t be loaded because it is damaged or missing necessary resources. Try reinstalling the bundle."
// The solution for me was to manually set the host applicaton. See https://github.com/CocoaPods/CocoaPods/issues/5022

class ServerAPI_Authentication: TestCase {
    override func setUp() {
        super.setUp()
        Log.msg("deviceUUID1: \(self.deviceUUID)")

        let exp = expectation(description: "\(#function)\(#line)")

        // Remove the user in case they already exist-- e.g., from a previous test.
        ServerAPI.session.removeUser { error in
            // There will be an error here if the user didn't exist already.
            exp.fulfill()
        }

        waitForExpectations(timeout: 10, handler: nil)
    }
    
    override func tearDown() {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
        super.tearDown()
    }
    
    func testAddUserWithoutAuthenticationDelegateFails() {
        let expectation = self.expectation(description: "authentication")
        ServerNetworking.session.authenticationDelegate = nil
        
        ServerAPI.session.addUser { error in
            XCTAssert(error != nil) 
            expectation.fulfill()
        }
        
        waitForExpectations(timeout: 10.0, handler: nil)
    }
    
    func testAddUserWithAuthenticationDelegateWorks() {
        let expectation = self.expectation(description: "authentication")
        
        ServerAPI.session.addUser { error in
            XCTAssert(error == nil)
            expectation.fulfill()
        }
        
        waitForExpectations(timeout: 10.0, handler: nil)
    }
    
    func testCheckCredsWithValidUserCredsWorks() {
        let expectation = self.expectation(description: "authentication")
        let addUserExpectation = self.expectation(description: "addUser")

        Log.msg("deviceUUID1: \(self.deviceUUID)")

        ServerAPI.session.addUser { error in
            XCTAssert(error == nil)
            addUserExpectation.fulfill()
            ServerAPI.session.checkCreds { userExists, error in
                XCTAssert(error == nil)
                XCTAssert(userExists!)
                expectation.fulfill()
            }
        }
        
        waitForExpectations(timeout: 10.0, handler: nil)
    }
    
    func testCheckCredsWithBadAuthenticationValuesFail() {
        let addUserExpectation = self.expectation(description: "addUser")
        let expectation = self.expectation(description: "authentication")
        
        ServerAPI.session.addUser { error in
            XCTAssert(error == nil)
            addUserExpectation.fulfill()
            
            self.authTokens[ServerConstants.GoogleHTTPAccessTokenKey] = "foobar"
            
            ServerAPI.session.checkCreds { userExists, error in
                XCTAssert(error == nil)
                XCTAssert(!userExists!)
                expectation.fulfill()
            }
        }
        
        waitForExpectations(timeout: 10.0, handler: nil)
    }
    
    func testRemoveUserWithBadAccessTokenFails() {
        let addUserExpectation = self.expectation(description: "addUser")
        let removeUserExpectation = self.expectation(description: "removeUser")
        
        ServerAPI.session.addUser { error in
            XCTAssert(error == nil)
            addUserExpectation.fulfill()
            
            self.authTokens[ServerConstants.GoogleHTTPAccessTokenKey] = "foobar"
            
            ServerAPI.session.removeUser { error in
                // Expect an error here because we have a bad access token.
                XCTAssert(error != nil)
                removeUserExpectation.fulfill()
            }
        }
        
        waitForExpectations(timeout: 10.0, handler: nil)
    }
    
    // TODO: *2* Check what happens when network fails. Do we get an error response back from ServerAPI.session.addUser? This issue applies to all ServerAPI calls.
    
    func testRemoveUserSucceeds() {
        let addUserExpectation = self.expectation(description: "addUser")
        let removeUserExpectation = self.expectation(description: "removeUser")
        
        ServerAPI.session.addUser { error in
            XCTAssert(error == nil)
            addUserExpectation.fulfill()
            
            ServerAPI.session.removeUser { error in
                XCTAssert(error == nil)
                removeUserExpectation.fulfill()
            }
        }
        
        waitForExpectations(timeout: 10.0, handler: nil)
    }
}
