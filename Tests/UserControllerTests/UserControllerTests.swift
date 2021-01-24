//
//  UserController.swift
//  Server
//
//  Created by Christopher Prince on 12/6/16.
//
//

import XCTest
@testable import Server
@testable import TestsCommon
import LoggerAPI
import Foundation
import ServerShared
import ServerAccount

class UserControllerTests: ServerTestCase {

    override func setUp() {
        super.setUp()        
    }
    
    func runAddUserSucceedsWhenAddingNewUser(testAccount:TestAccount) {
        let deviceUUID = Foundation.UUID().uuidString
        let sharingGroupUUID = UUID().uuidString
        
        guard let addUserResponse = addNewUser(testAccount:testAccount, sharingGroupUUID: sharingGroupUUID, deviceUUID:deviceUUID) else {
            XCTFail()
            return
        }
        
        guard let userId = addUserResponse.userId else {
            XCTFail()
            return
        }
        
        let result = UserRepository(self.db).lookup(key: .userId(userId), modelInit: User.init)
        switch result {
        case .error(let error):
            XCTFail("\(error)")
            
        case .found(let object):
            let user = object as! User
            
            // Make sure that the database has a cloud folder name-- but only if that account type needs it.
            if TestAccount.needsCloudFolder(testAccount) {
                XCTAssert(user.cloudFolderName == ServerTestCase.cloudFolderName)
            }
            
        case .noObjectFound:
            XCTFail("No User Found")
        }
        
        // Make sure the initial file was created in users cloud storage, if one is configured.
        if let fileName = Configuration.server.owningUserAccountCreation.initialFileName {
            let options = CloudStorageFileNameOptions(cloudFolderName: ServerTestCase.cloudFolderName, mimeType: "text/plain")
            self.lookupFile(forOwningTestAccount: testAccount, cloudFileName: fileName, options: options)
        }
    }
    
    func testAddUserSucceedsWhenAddingNewUser() {
        let testAccount:TestAccount = .primaryOwningAccount
        runAddUserSucceedsWhenAddingNewUser(testAccount:testAccount)
    }
    
    // Trying to reproduce client issue.
    func testAddUserSucceedsWhenAddingNewDropboxUser() {
        let testAccount:TestAccount = .dropbox1
        runAddUserSucceedsWhenAddingNewUser(testAccount:testAccount)
    }
    
    func testAddUserWithSharingGroupNameWorks() {
        let sharingGroupUUID = UUID().uuidString
        let deviceUUID = Foundation.UUID().uuidString
        let testAccount:TestAccount = .primaryOwningAccount
        let sharingGroupName = "SharingGroup765"
        
        guard let _ = addNewUser(testAccount:testAccount, sharingGroupUUID: sharingGroupUUID, deviceUUID:deviceUUID, sharingGroupName:sharingGroupName) else {
            XCTFail()
            return
        }
        
        guard let (_, sharingGroups) = getIndex() else {
            XCTFail()
            return
        }
        
        guard sharingGroups.count == 1 else {
            XCTFail()
            return
        }
        
        XCTAssert(sharingGroups[0].sharingGroupUUID == sharingGroupUUID)
        XCTAssert(sharingGroups[0].sharingGroupName == sharingGroupName)
        XCTAssert(sharingGroups[0].deleted == false)
    }
    
    func testAddUserFailsWhenAddingExistingUser() {
        let sharingGroupUUID = UUID().uuidString
        let deviceUUID = Foundation.UUID().uuidString
        self.addNewUser(sharingGroupUUID: sharingGroupUUID, deviceUUID:deviceUUID)
        
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
        let sharingGroupUUID1 = UUID().uuidString
        
        addNewUser(testAccount:testAccount, sharingGroupUUID: sharingGroupUUID1, deviceUUID:deviceUUID)
        
        // remove
        performServerTest { expectation, creds in
            let headers = self.setupHeaders(testUser: testAccount, accessToken: creds.accessToken, deviceUUID:deviceUUID)
            
            self.performRequest(route: ServerEndpoints.removeUser, headers: headers) { response, dict in
                Log.info("Status code: \(response!.statusCode)")
                XCTAssert(response!.statusCode == .OK, "removeUser failed")
                expectation.fulfill()
            }
        }
        
        let sharingGroupUUID2 = UUID().uuidString
        addNewUser(testAccount:testAccount, sharingGroupUUID: sharingGroupUUID2, deviceUUID:deviceUUID)
    }
    
    func testCheckCredsWhenUserDoesExist() {
        let testingAccount:TestAccount = .primaryOwningAccount
        let deviceUUID = Foundation.UUID().uuidString
        let sharingGroupUUID = UUID().uuidString

        self.addNewUser(testAccount: testingAccount, sharingGroupUUID: sharingGroupUUID, deviceUUID:deviceUUID)

        performServerTest(testAccount: testingAccount) { expectation, creds in
            let headers = self.setupHeaders(testUser: testingAccount, accessToken: creds.accessToken, deviceUUID:deviceUUID)
            
            self.performRequest(route: ServerEndpoints.checkCreds, headers: headers) { response, dict in
                Log.info("Status code: \(String(describing: response?.statusCode))")
                XCTAssert(response?.statusCode == .OK, "checkCreds failed")
                
                if let dict = dict,
                    let checkCredsResponse = try? CheckCredsResponse.decode(dict) {
                    XCTAssert(checkCredsResponse.userInfo?.fullUserName != nil)
                    XCTAssert(checkCredsResponse.userInfo?.userId != nil)
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
                Log.info("Status code: \(String(describing: response?.statusCode))")
                XCTAssert(response?.statusCode == .unauthorized, "checkCreds failed")
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
        let sharingGroupUUID = Foundation.UUID().uuidString

        self.addNewUser(sharingGroupUUID: sharingGroupUUID, deviceUUID:deviceUUID)

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
    
    func testThatFilesUploadedByUserMarkedAsDeletedWhenUserRemoved() {
        let deviceUUID = Foundation.UUID().uuidString
        let sharingGroupUUID = Foundation.UUID().uuidString

        guard let _ = self.addNewUser(sharingGroupUUID: sharingGroupUUID, deviceUUID:deviceUUID) else {
            XCTFail()
            return
        }
        
        // Upload a file.
        guard let uploadResult = uploadTextFile(deviceUUID:deviceUUID, addUser: .no(sharingGroupUUID: sharingGroupUUID), fileLabel: UUID().uuidString) else {
            XCTFail()
            return
        }

        // Remove the user
        performServerTest { expectation, creds in
            let headers = self.setupHeaders(testUser: .primaryOwningAccount, accessToken: creds.accessToken, deviceUUID:deviceUUID)
            
            self.performRequest(route: ServerEndpoints.removeUser, headers: headers) { response, dict in
                Log.info("Status code: \(response!.statusCode)")
                XCTAssert(response!.statusCode == .OK, "removeUser failed")
                expectation.fulfill()
            }
        }
        
        // Make sure file was deleted.
        
        let fileIndexResult = FileIndexRepository(db).fileIndex(forSharingGroupUUID: sharingGroupUUID)
        switch fileIndexResult {
        case .fileIndex(let fileIndex):
            // We don't get any file index rows for this user with the sharing group when the user was deleted.
            guard fileIndex.count == 0 else {
                XCTFail("fileIndex.count: \(fileIndex.count)")
                return
            }
            

        case .error(_):
            XCTFail()
        }
        
        let key = FileIndexRepository.LookupKey.primaryKeys(sharingGroupUUID: sharingGroupUUID, fileUUID: uploadResult.request.fileUUID)
        let result = FileIndexRepository(db).lookup(key: key, modelInit: FileIndex.init)
        switch result {
        case .found(let obj):
            guard let fileIndexObj = obj as? FileIndex else {
                XCTFail()
                return
            }
            
            XCTAssert(fileIndexObj.deleted == true)
        
        default:
            XCTFail()
            return
        }
    }
}

