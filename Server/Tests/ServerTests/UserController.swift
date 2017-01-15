//
//  UserController.swift
//  Server
//
//  Created by Christopher Prince on 12/6/16.
//
//

import XCTest
@testable import Server
import LoggerAPI

class UserControllerTests: ServerTestCase {

    override func setUp() {
        super.setUp()        
        _ = UserRepository.remove()
        _ = UserRepository.create()
    }
    
    func addNewUser() {
        self.performServerTest { expectation, googleCreds in
            let headers = self.setupHeaders(accessToken: googleCreds.accessToken)
            self.performRequest(route: ServerEndpoints.addUser, headers: headers) { response, dict in
                Log.info("Status code: \(response!.statusCode)")
                XCTAssert(response!.statusCode == .OK, "Did not work on addUser request")
                expectation.fulfill()
            }
        }
    }
    
    func testAddUserSucceedsWhenAddingNewUser() {
        self.addNewUser()
    }
    
    func testAddUserFailsWhenAddingExistingUser() {
        self.addNewUser()
            
        performServerTest { expectation, googleCreds in
            let headers = self.setupHeaders(accessToken: googleCreds.accessToken)
            self.performRequest(route: ServerEndpoints.addUser, headers: headers) { response, dict in
                Log.info("Status code: \(response!.statusCode)")
                XCTAssert(response!.statusCode == .internalServerError, "Worked on addUser request")
                expectation.fulfill()
            }
        }
    }
    
    func testCheckCredsWhenUserDoesExist() {
        self.addNewUser()
            
        performServerTest { expectation, googleCreds in
            let headers = self.setupHeaders(accessToken: googleCreds.accessToken)
            
            self.performRequest(route: ServerEndpoints.checkCreds, headers: headers) { response, dict in
                Log.info("Status code: \(response!.statusCode)")
                XCTAssert(response!.statusCode == .OK, "checkCreds failed")
                expectation.fulfill()
            }
        }
    }
    
    func testCheckCredsWhenUserDoesNotExist() {
        performServerTest { expectation, googleCreds in
            let headers = self.setupHeaders(accessToken: googleCreds.accessToken)
            
            self.performRequest(route: ServerEndpoints.checkCreds, headers: headers) { response, dict in
                Log.info("Status code: \(response!.statusCode)")
                XCTAssert(response!.statusCode == .unauthorized, "checkCreds failed")
                expectation.fulfill()
            }
        }
    }
    
    func testCheckCredsWithBadAccessToken() {
        performServerTest { expectation, googleCreds in
            let headers = self.setupHeaders(accessToken: "Some junk for access token")
            
            self.performRequest(route: ServerEndpoints.checkCreds, headers: headers) { response, dict in
                Log.info("Status code: \(response!.statusCode)")
                XCTAssert(response!.statusCode == .unauthorized, "checkCreds failed")
                expectation.fulfill()
            }
        }
    }
    
    func testRemoveUserFailsWithNonExistingUser() {
        // Don't create the user first.
        performServerTest { expectation, googleCreds in
            let headers = self.setupHeaders(accessToken: googleCreds.accessToken)
            
            self.performRequest(route: ServerEndpoints.removeUser, headers: headers) { response, dict in
                Log.info("Status code: \(response!.statusCode)")
                XCTAssert(response!.statusCode == .unauthorized, "removeUser did not fail")
                expectation.fulfill()
            }
        }
    }
    
    func testRemoveUserSucceedsWithExistingUser() {
        self.addNewUser()

        performServerTest { expectation, googleCreds in
            let headers = self.setupHeaders(accessToken: googleCreds.accessToken)
            
            self.performRequest(route: ServerEndpoints.removeUser, headers: headers) { response, dict in
                Log.info("Status code: \(response!.statusCode)")
                XCTAssert(response!.statusCode == .OK, "removeUser failed")
                expectation.fulfill()
            }
        }
        
        // Confirm that user doesn't exist any more
        testCheckCredsWhenUserDoesNotExist()
    }
}
