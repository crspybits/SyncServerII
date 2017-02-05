import XCTest
@testable import SyncServer

// After creating this project afresh, I was getting errors like: "...couldn’t be loaded because it is damaged or missing necessary resources. Try reinstalling the bundle."
// The solution for me was to manually set the host applicaton. See https://github.com/CocoaPods/CocoaPods/issues/5022

class Authentication: TestCase {    
    override func setUp() {
        super.setUp()
        
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
                // Expect an error here because we a bad access token.
                XCTAssert(error != nil)
                removeUserExpectation.fulfill()
            }
        }
        
        waitForExpectations(timeout: 10.0, handler: nil)
    }
    
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
