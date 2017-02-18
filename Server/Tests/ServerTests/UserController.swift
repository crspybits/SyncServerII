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
import PerfectLib

class UserControllerTests: ServerTestCase {

    override func setUp() {
        super.setUp()        
    }
    
    func testAddUserSucceedsWhenAddingNewUser() {
        let deviceUUID = PerfectLib.UUID().string
        self.addNewUser(deviceUUID:deviceUUID)
    }
    
    func testAddUserFailsWhenAddingExistingUser() {
        let deviceUUID = PerfectLib.UUID().string
        self.addNewUser(deviceUUID:deviceUUID)
            
        performServerTest { expectation, googleCreds in
            let headers = self.setupHeaders(accessToken: googleCreds.accessToken, deviceUUID:deviceUUID)
            self.performRequest(route: ServerEndpoints.addUser, headers: headers) { response, dict in
                Log.info("Status code: \(response!.statusCode)")
                XCTAssert(response!.statusCode == .internalServerError, "Worked on addUser request")
                expectation.fulfill()
            }
        }
    }
    
    func testCheckCredsWhenUserDoesExist() {
        let deviceUUID = PerfectLib.UUID().string
        self.addNewUser(deviceUUID:deviceUUID)
            
        performServerTest { expectation, googleCreds in
            let headers = self.setupHeaders(accessToken: googleCreds.accessToken, deviceUUID:deviceUUID)
            
            self.performRequest(route: ServerEndpoints.checkCreds, headers: headers) { response, dict in
                Log.info("Status code: \(response!.statusCode)")
                XCTAssert(response!.statusCode == .OK, "checkCreds failed")
                expectation.fulfill()
            }
        }
    }
    
    func testCheckCredsWhenUserDoesNotExist() {
        let deviceUUID = PerfectLib.UUID().string

        performServerTest { expectation, googleCreds in
            let headers = self.setupHeaders(accessToken: googleCreds.accessToken, deviceUUID:deviceUUID)
            
            self.performRequest(route: ServerEndpoints.checkCreds, headers: headers) { response, dict in
                Log.info("Status code: \(response!.statusCode)")
                XCTAssert(response!.statusCode == .unauthorized, "checkCreds failed")
                expectation.fulfill()
            }
        }
    }
    
    func testCheckCredsWithBadAccessToken() {
        let deviceUUID = PerfectLib.UUID().string

        performServerTest { expectation, googleCreds in
            let headers = self.setupHeaders(accessToken: "Some junk for access token", deviceUUID:deviceUUID)
            
            self.performRequest(route: ServerEndpoints.checkCreds, headers: headers) { response, dict in
                Log.info("Status code: \(response!.statusCode)")
                XCTAssert(response!.statusCode == .unauthorized, "checkCreds failed")
                expectation.fulfill()
            }
        }
    }
    
    func testRemoveUserFailsWithNonExistingUser() {
        let deviceUUID = PerfectLib.UUID().string

        // Don't create the user first.
        performServerTest { expectation, googleCreds in
            let headers = self.setupHeaders(accessToken: googleCreds.accessToken, deviceUUID:deviceUUID)
            
            self.performRequest(route: ServerEndpoints.removeUser, headers: headers) { response, dict in
                Log.info("Status code: \(response!.statusCode)")
                XCTAssert(response!.statusCode == .unauthorized, "removeUser did not fail")
                expectation.fulfill()
            }
        }
    }
    
    func testRemoveUserSucceedsWithExistingUser() {
        let deviceUUID = PerfectLib.UUID().string
        self.addNewUser(deviceUUID:deviceUUID)

        performServerTest { expectation, googleCreds in
            let headers = self.setupHeaders(accessToken: googleCreds.accessToken, deviceUUID:deviceUUID)
            
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
