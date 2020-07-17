//
//  SpecificDatabaseTests.swift
//  Server
//
//  Created by Christopher Prince on 12/18/16.
//
//

import XCTest
@testable import Server
@testable import TestsCommon
import LoggerAPI
import HeliumLogger
import Credentials
import CredentialsGoogle
import Foundation
import ServerShared

class SpecificDatabaseTests_FileIndex: ServerTestCase {
    var accountManager: AccountManager!
    var userRepo: UserRepository!
    
    override func setUp() {
        super.setUp()
        userRepo = UserRepository(db)
        accountManager = AccountManager(userRepository: userRepo)
    }
    
    override func tearDown() {
        super.tearDown()
    }
    
    func doAddFileIndex(userId:UserId = 1, sharingGroupUUID:String, createSharingGroup: Bool, changeResolverName: String? = nil) -> FileIndex? {

        if createSharingGroup {
            guard case .success = SharingGroupRepository(db).add(sharingGroupUUID: sharingGroupUUID) else {
                XCTFail()
                return nil
            }
            
            guard case .success = SharingGroupUserRepository(db).add(sharingGroupUUID: sharingGroupUUID, userId: userId, permission: .write, owningUserId: nil) else {
                XCTFail()
                return nil
            }
        }
        
        let fileIndex = FileIndex()
        fileIndex.lastUploadedCheckSum = "abcde"
        fileIndex.deleted = false
        fileIndex.fileUUID = Foundation.UUID().uuidString
        fileIndex.deviceUUID = Foundation.UUID().uuidString
        fileIndex.fileVersion = 1
        fileIndex.mimeType = "text/plain"
        fileIndex.userId = userId
        fileIndex.appMetaData = "{ \"foo\": \"bar\" }"
        fileIndex.creationDate = Date()
        fileIndex.updateDate = Date()
        fileIndex.sharingGroupUUID = sharingGroupUUID
        fileIndex.changeResolverName = changeResolverName
        
        let result1 = FileIndexRepository(db).add(fileIndex: fileIndex)
        guard case .success(let uploadId) = result1 else {
            XCTFail()
            return nil
        }

        fileIndex.fileIndexId = uploadId
        
        return fileIndex
    }

    func testAddFileIndex() {
        let user1 = User()
        user1.username = "Chris"
        user1.accountType = AccountScheme.google.accountName
        user1.creds = "{\"accessToken\": \"SomeAccessTokenValue1\"}"
        user1.credsId = "100"
        
        guard let userId = userRepo.add(user: user1, accountManager: accountManager, validateJSON: false) else {
            XCTFail("Bad credentialsId!")
            return
        }
        
        let sharingGroupUUID = UUID().uuidString
        guard let _ = doAddFileIndex(userId:userId, sharingGroupUUID: sharingGroupUUID, createSharingGroup: true) else {
            XCTFail()
            return
        }
    }
    
    func testAddFileIndexWithChangeResolver() {
        let user1 = User()
        user1.username = "Chris"
        user1.accountType = AccountScheme.google.accountName
        user1.creds = "{\"accessToken\": \"SomeAccessTokenValue1\"}"
        user1.credsId = "100"
        
        guard let userId = userRepo.add(user: user1, accountManager: accountManager, validateJSON: false) else {
            XCTFail("Bad credentialsId!")
            return
        }
        
        let sharingGroupUUID = UUID().uuidString
        guard let _ = doAddFileIndex(userId:userId, sharingGroupUUID: sharingGroupUUID, createSharingGroup: true, changeResolverName: "Foobar") else {
            XCTFail()
            return
        }
    }

    func testUpdateFileIndexWithNoChanges() {
        let user1 = User()
        user1.username = "Chris"
        user1.accountType = AccountScheme.google.accountName
        user1.creds = "{\"accessToken\": \"SomeAccessTokenValue1\"}"
        user1.credsId = "100"
        
        guard let userId = userRepo.add(user: user1, accountManager: accountManager, validateJSON: false) else {
            XCTFail("Bad credentialsId!")
            return
        }
        
        let sharingGroupUUID = UUID().uuidString
        guard let fileIndex = doAddFileIndex(userId:userId, sharingGroupUUID: sharingGroupUUID, createSharingGroup: true) else {
            XCTFail()
            return
        }
        
        XCTAssert(FileIndexRepository(db).update(fileIndex: fileIndex))
    }
    
    func testUpdateFileIndexWithAChange() {
        let user1 = User()
        user1.username = "Chris"
        user1.accountType = AccountScheme.google.accountName
        user1.creds = "{\"accessToken\": \"SomeAccessTokenValue1\"}"
        user1.credsId = "100"
        let sharingGroupUUID = UUID().uuidString

        // 6/12/19; Just added the JSON validation parameter. I have *no* idea how this was working before this. It ought to have required the server to be running for it to work.
        guard let userId = userRepo.add(user: user1, accountManager: accountManager, validateJSON: false) else {
            XCTFail("Bad credentialsId!")
            return
        }
        
        guard let fileIndex = doAddFileIndex(userId:userId, sharingGroupUUID: sharingGroupUUID, createSharingGroup: true) else {
            XCTFail()
            return
        }
        
        fileIndex.fileVersion = 2
        XCTAssert(FileIndexRepository(db).update(fileIndex: fileIndex))
    }
    
    func testUpdateFileIndexFailsWithoutFileIndexId() {
        let user1 = User()
        user1.username = "Chris"
        user1.accountType = AccountScheme.google.accountName
        user1.creds = "{\"accessToken\": \"SomeAccessTokenValue1\"}"
        user1.credsId = "100"
        let sharingGroupUUID = UUID().uuidString

        guard let userId = userRepo.add(user: user1, accountManager: accountManager, validateJSON: false) else {
            XCTFail("Bad credentialsId!")
            return
        }
        
        guard let fileIndex = doAddFileIndex(userId:userId, sharingGroupUUID: sharingGroupUUID, createSharingGroup: true) else {
            XCTFail()
            return
        }
        fileIndex.fileIndexId = nil
        XCTAssert(!FileIndexRepository(db).update(fileIndex: fileIndex))
    }
    
    func testUpdateUploadSucceedsWithNilAppMetaData() {
        let user1 = User()
        user1.username = "Chris"
        user1.accountType = AccountScheme.google.accountName
        user1.creds = "{\"accessToken\": \"SomeAccessTokenValue1\"}"
        user1.credsId = "100"
        let sharingGroupUUID = UUID().uuidString

        guard let userId = userRepo.add(user: user1, accountManager: accountManager, validateJSON: false) else {
            XCTFail("Bad credentialsId!")
            return
        }
        
        guard let fileIndex = doAddFileIndex(userId:userId, sharingGroupUUID: sharingGroupUUID, createSharingGroup: true) else {
            XCTFail()
            return
        }
        
        fileIndex.appMetaData = nil
        XCTAssert(FileIndexRepository(db).update(fileIndex: fileIndex))
    }
    
    func testLookupFromFileIndex() {
        let user1 = User()
        user1.username = "Chris"
        user1.accountType = AccountScheme.google.accountName
        user1.creds = "{\"accessToken\": \"SomeAccessTokenValue1\"}"
        user1.credsId = "100"
        let sharingGroupUUID = UUID().uuidString
        let changeResolverName = "Foobar"
        
        guard let userId = userRepo.add(user: user1, accountManager: accountManager, validateJSON: false) else {
            XCTFail("Bad credentialsId!")
            return
        }
        
        guard let fileIndex1 = doAddFileIndex(userId:userId, sharingGroupUUID: sharingGroupUUID, createSharingGroup: true, changeResolverName: changeResolverName) else {
            XCTFail()
            return
        }
        
        let result = FileIndexRepository(db).lookup(key: .fileIndexId(fileIndex1.fileIndexId), modelInit: FileIndex.init)
        switch result {
        case .error(let error):
            XCTFail("\(error)")
            
        case .found(let object):
            let fileIndex2 = object as! FileIndex
            XCTAssert(fileIndex1.lastUploadedCheckSum != nil && fileIndex1.lastUploadedCheckSum == fileIndex2.lastUploadedCheckSum)
            XCTAssert(fileIndex1.deleted != nil && fileIndex1.deleted == fileIndex2.deleted)
            XCTAssert(fileIndex1.fileUUID != nil && fileIndex1.fileUUID == fileIndex2.fileUUID)
            XCTAssert(fileIndex1.deviceUUID != nil && fileIndex1.deviceUUID == fileIndex2.deviceUUID)

            XCTAssert(fileIndex1.fileVersion != nil && fileIndex1.fileVersion == fileIndex2.fileVersion)
            XCTAssert(fileIndex1.mimeType != nil && fileIndex1.mimeType == fileIndex2.mimeType)
            XCTAssert(fileIndex1.userId != nil && fileIndex1.userId == fileIndex2.userId)
            XCTAssert(fileIndex1.appMetaData != nil && fileIndex1.appMetaData == fileIndex2.appMetaData)
            XCTAssert(fileIndex1.sharingGroupUUID != nil && fileIndex1.sharingGroupUUID == fileIndex2.sharingGroupUUID)
            XCTAssert(fileIndex2.changeResolverName == changeResolverName)

        case .noObjectFound:
            XCTFail("No Upload Found")
        }
    }

    func testFileIndexWithNoFiles() {
        let user1 = User()
        user1.username = "Chris"
        user1.accountType = AccountScheme.google.accountName
        user1.creds = "{\"accessToken\": \"SomeAccessTokenValue1\"}"
        user1.credsId = "100"
        let sharingGroupUUID = UUID().uuidString

        guard let userId = userRepo.add(user: user1, accountManager: accountManager, validateJSON: false) else {
            XCTFail("Bad credentialsId!")
            return
        }
        
        guard case .success = SharingGroupRepository(db).add(sharingGroupUUID: sharingGroupUUID) else {
            XCTFail()
            return
        }
        
        guard case .success = SharingGroupUserRepository(db).add(sharingGroupUUID: sharingGroupUUID, userId: userId, permission: .admin, owningUserId: nil) else {
            XCTFail()
            return
        }
        
        let fileIndexResult = FileIndexRepository(db).fileIndex(forSharingGroupUUID: sharingGroupUUID)
        switch fileIndexResult {
        case .fileIndex(let fileIndex):
            XCTAssert(fileIndex.count == 0)
        case .error(_):
            XCTFail()
        }
    }

    func testFileIndexWithOneFile() {
        let user1 = User()
        user1.username = "Chris"
        user1.accountType = AccountScheme.google.accountName
        user1.creds = "{\"accessToken\": \"SomeAccessTokenValue1\"}"
        user1.credsId = "100"
        let sharingGroupUUID = UUID().uuidString

        guard let userId = userRepo.add(user: user1, accountManager: accountManager, validateJSON: false) else {
            XCTFail()
            return
        }
        
        guard case .success = SharingGroupRepository(db).add(sharingGroupUUID: sharingGroupUUID) else {
            XCTFail()
            return
        }
        
        guard case .success = SharingGroupUserRepository(db).add(sharingGroupUUID: sharingGroupUUID, userId: userId, permission: .read, owningUserId: nil) else {
            XCTFail()
            return
        }

        guard let fileIndexInserted = doAddFileIndex(userId: userId, sharingGroupUUID: sharingGroupUUID, createSharingGroup: false) else {
            XCTFail()
            return
        }

        let fileIndexResult = FileIndexRepository(db).fileIndex(forSharingGroupUUID: sharingGroupUUID)
        switch fileIndexResult {
        case .fileIndex(let fileIndex):
            guard fileIndex.count == 1 else {
                XCTFail()
                return
            }
            
            XCTAssert(fileIndexInserted.fileUUID == fileIndex[0].fileUUID)
            XCTAssert(fileIndexInserted.fileVersion == fileIndex[0].fileVersion)
            XCTAssert(fileIndexInserted.mimeType == fileIndex[0].mimeType)
            XCTAssert(fileIndexInserted.deleted == fileIndex[0].deleted)
            XCTAssert(fileIndex[0].cloudStorageType == AccountScheme.google.cloudStorageType)
            
        case .error(_):
            XCTFail()
        }
    }
}

//extension SpecificDatabaseTests {
//    static var allTests : [(String, (SpecificDatabaseTests) -> () throws -> Void)] {
//        return [
//            ("testUpdateToNextMasterVersion", testUpdateToNextMasterVersion),
//            ("testUpdateToNextTwiceMasterVersion", testUpdateToNextTwiceMasterVersion),
//            ("testUpdateToNextFailsWithWrongExpectedMasterVersion", testUpdateToNextFailsWithWrongExpectedMasterVersion),
//            ("testAddFileIndex", testAddFileIndex),
//            ("testUpdateFileIndexWithNoChanges", testUpdateFileIndexWithNoChanges),
//            ("testUpdateFileIndexWithAChange", testUpdateFileIndexWithAChange),
//            ("testUpdateFileIndexFailsWithoutFileIndexId", testUpdateFileIndexFailsWithoutFileIndexId),
//            ("testUpdateUploadSucceedsWithNilAppMetaData", testUpdateUploadSucceedsWithNilAppMetaData),
//            ("testLookupFromFileIndex", testLookupFromFileIndex),
//            ("testFileIndexWithNoFiles", testFileIndexWithNoFiles),
//            ("testFileIndexWithOneFile", testFileIndexWithOneFile),
//            ("testAddDeviceUUID", testAddDeviceUUID),
//            ("testAddDeviceUUIDFailsAfterMax", testAddDeviceUUIDFailsAfterMax),
//            ("testAddDeviceUUIDDoesNotFailFailsAfterMaxWithNilMax", testAddDeviceUUIDDoesNotFailFailsAfterMaxWithNilMax),
//            ("testLookupFromDeviceUUID", testLookupFromDeviceUUID)
//        ]
//    }
//
//    func testLinuxTestSuiteIncludesAllTests() {
//        linuxTestSuiteIncludesAllTests(testType: SpecificDatabaseTests.self)
//    }
//}
