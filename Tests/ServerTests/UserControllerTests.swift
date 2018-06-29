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
import Foundation
import SyncServerShared

class UserControllerTests: ServerTestCase, LinuxTestable {

    override func setUp() {
        super.setUp()        
    }
    
    func testAddUserSucceedsWhenAddingNewUser() {
        let deviceUUID = Foundation.UUID().uuidString
        let testAccount:TestAccount = .primaryOwningAccount
        
        guard let addUserResponse = addNewUser(testAccount:testAccount, deviceUUID:deviceUUID) else {
            XCTFail()
            return
        }
        
        XCTAssert(addUserResponse.sharingGroupId != nil)
        
        // Make sure that the database has a cloud folder name-- but only if that account type needs it.
        if TestAccount.needsCloudFolder(testAccount) {
            let result = UserRepository(self.db).lookup(key: .userId(addUserResponse.userId), modelInit: User.init)
            switch result {
            case .error(let error):
                XCTFail("\(error)")
                
            case .found(let object):
                let user = object as! User
                XCTAssert(user.cloudFolderName == ServerTestCase.cloudFolderName)
                
            case .noObjectFound:
                XCTFail("No User Found")
            }
        }
        
        // Make sure the initial file was created in users cloud storage, if one is configured.
        if let fileName = Constants.session.owningUserAccountCreation.initialFileName {
            let options = CloudStorageFileNameOptions(cloudFolderName: ServerTestCase.cloudFolderName, mimeType: "text/plain")
            self.lookupFile(testAccount: testAccount, cloudFileName: fileName, options: options)
        }
    }
    
    func testAddUserFailsWhenAddingExistingUser() {
        let deviceUUID = Foundation.UUID().uuidString
        self.addNewUser(deviceUUID:deviceUUID)
            
        performServerTest { expectation, creds in
            let headers = self.setupHeaders(testUser: .primaryOwningAccount, accessToken: creds.accessToken, deviceUUID:deviceUUID)
            self.performRequest(route: ServerEndpoints.addUser, headers: headers) { response, dict in
                Log.info("Status code: \(response!.statusCode)")
                XCTAssert(response!.statusCode == .internalServerError, "Worked on addUser request")
                expectation.fulfill()
            }
        }
    }
    
    // Purpose is to check if second add user fails because the initial file is there.
    func testAddRemoveAddWorks() {
        let deviceUUID = Foundation.UUID().uuidString
        let testAccount:TestAccount = .primaryOwningAccount
        
        addNewUser(testAccount:testAccount, deviceUUID:deviceUUID)
        
        // remove
        performServerTest { expectation, creds in
            let headers = self.setupHeaders(testUser: testAccount, accessToken: creds.accessToken, deviceUUID:deviceUUID)
            
            self.performRequest(route: ServerEndpoints.removeUser, headers: headers) { response, dict in
                Log.info("Status code: \(response!.statusCode)")
                XCTAssert(response!.statusCode == .OK, "removeUser failed")
                expectation.fulfill()
            }
        }
        
        addNewUser(testAccount:testAccount, deviceUUID:deviceUUID)
    }
    
    func testCheckCredsWhenUserDoesExist() {
        let deviceUUID = Foundation.UUID().uuidString
        self.addNewUser(deviceUUID:deviceUUID)
            
        performServerTest { expectation, creds in
            let headers = self.setupHeaders(testUser: .primaryOwningAccount, accessToken: creds.accessToken, deviceUUID:deviceUUID)
            
            self.performRequest(route: ServerEndpoints.checkCreds, headers: headers) { response, dict in
                Log.info("Status code: \(response!.statusCode)")
                XCTAssert(response!.statusCode == .OK, "checkCreds failed")
                
                if let dict = dict, let checkCredsResponse = CheckCredsResponse(json: dict) {
                    XCTAssert(checkCredsResponse.userId != nil)
                }
                else {
                    XCTFail()
                }
                
                expectation.fulfill()
            }
        }
    }
    
    func testCheckCredsWhenUserDoesNotExist() {
        let deviceUUID = Foundation.UUID().uuidString

        performServerTest { expectation, creds in
            let headers = self.setupHeaders(testUser: .primaryOwningAccount, accessToken: creds.accessToken, deviceUUID:deviceUUID)
            
            self.performRequest(route: ServerEndpoints.checkCreds, headers: headers) { response, dict in
                Log.info("Status code: \(response!.statusCode)")
                XCTAssert(response!.statusCode == .unauthorized, "checkCreds failed")
                expectation.fulfill()
            }
        }
    }
    
    func testCheckCredsWithBadAccessToken() {
        let deviceUUID = Foundation.UUID().uuidString

        performServerTest { expectation, creds in
            let headers = self.setupHeaders(testUser: .primaryOwningAccount, accessToken: "Some junk for access token", deviceUUID:deviceUUID)
            
            self.performRequest(route: ServerEndpoints.checkCreds, headers: headers) { response, dict in
                Log.info("Status code: \(response!.statusCode)")
                XCTAssert(response!.statusCode == .unauthorized, "checkCreds failed")
                expectation.fulfill()
            }
        }
    }
    
    func testRemoveUserFailsWithNonExistingUser() {
        let deviceUUID = Foundation.UUID().uuidString

        // Don't create the user first.
        performServerTest { expectation, creds in
            let headers = self.setupHeaders(testUser: .primaryOwningAccount, accessToken: creds.accessToken, deviceUUID:deviceUUID)
            
            self.performRequest(route: ServerEndpoints.removeUser, headers: headers) { response, dict in
                Log.info("Status code: \(response!.statusCode)")
                XCTAssert(response!.statusCode == .unauthorized, "removeUser did not fail")
                expectation.fulfill()
            }
        }
    }
    
    func testRemoveUserSucceedsWithExistingUser() {
        let deviceUUID = Foundation.UUID().uuidString
        self.addNewUser(deviceUUID:deviceUUID)

        performServerTest { expectation, creds in
            let headers = self.setupHeaders(testUser: .primaryOwningAccount, accessToken: creds.accessToken, deviceUUID:deviceUUID)
            
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

extension UserControllerTests {
    static var allTests : [(String, (UserControllerTests) -> () throws -> Void)] {
        return [
            ("testAddUserSucceedsWhenAddingNewUser", testAddUserSucceedsWhenAddingNewUser),
            ("testAddUserFailsWhenAddingExistingUser", testAddUserFailsWhenAddingExistingUser),
            ("testAddRemoveAddWorks", testAddRemoveAddWorks),
            ("testCheckCredsWhenUserDoesExist", testCheckCredsWhenUserDoesExist),
            ("testCheckCredsWhenUserDoesNotExist", testCheckCredsWhenUserDoesNotExist),
            ("testCheckCredsWithBadAccessToken", testCheckCredsWithBadAccessToken),
            ("testRemoveUserFailsWithNonExistingUser", testRemoveUserFailsWithNonExistingUser),
            ("testRemoveUserSucceedsWithExistingUser", testRemoveUserSucceedsWithExistingUser)
        ]
    }
    
    func testLinuxTestSuiteIncludesAllTests() {
        linuxTestSuiteIncludesAllTests(testType: UserControllerTests.self)
    }
}

