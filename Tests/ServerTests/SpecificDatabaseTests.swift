//
//  SpecificDatabaseTests.swift
//  Server
//
//  Created by Christopher Prince on 12/18/16.
//
//

import XCTest
@testable import Server
import LoggerAPI
import HeliumLogger
import Credentials
import CredentialsGoogle
import Foundation
import SyncServerShared

class SpecificDatabaseTests: ServerTestCase, LinuxTestable {

    override func setUp() {
        super.setUp()
    }
    
    override func tearDown() {
        super.tearDown()
    }
            
    func checkMasterVersion(sharingGroupUUID:String, version:Int64) {
        let result = MasterVersionRepository(db).lookup(key: .sharingGroupUUID(sharingGroupUUID), modelInit: MasterVersion.init)
        switch result {
        case .error(let error):
            XCTFail("\(error)")
            
        case .found(let object):
            let masterVersion = object as! MasterVersion
            XCTAssert(masterVersion.masterVersion == version && masterVersion.sharingGroupUUID == sharingGroupUUID)

        case .noObjectFound:
            XCTFail("No MasterVersion Found")
        }
    }

    func doUpdateToNextMasterVersion(currentMasterVersion:MasterVersionInt, sharingGroupUUID: String, expectedError: Bool = false) {
        
        let current = MasterVersion()
        current.sharingGroupUUID = sharingGroupUUID
        current.masterVersion = currentMasterVersion
        
        let result = MasterVersionRepository(db).updateToNext(current: current)
        
        if case .success = result {
            if expectedError {
                XCTFail()
            }
            else {
                XCTAssert(true)
            }
        }
        else {
            if expectedError {
                XCTAssert(true)
            }
            else {
                XCTFail()
            }
        }
    }
    
    func testUpdateToNextMasterVersion() {
        let sharingGroupUUID = UUID().uuidString
        guard case .success = SharingGroupRepository(db).add(sharingGroupUUID: sharingGroupUUID) else {
            XCTFail()
            return
        }
        
        XCTAssert(MasterVersionRepository(db).initialize(sharingGroupUUID: sharingGroupUUID))
        doUpdateToNextMasterVersion(currentMasterVersion: 0, sharingGroupUUID: sharingGroupUUID)
        checkMasterVersion(sharingGroupUUID: sharingGroupUUID, version: 1)
    }

    func testUpdateToNextTwiceMasterVersion() {
        let sharingGroupUUID = UUID().uuidString

        guard case .success = SharingGroupRepository(db).add(sharingGroupUUID: sharingGroupUUID) else {
            XCTFail()
            return
        }
        
        XCTAssert(MasterVersionRepository(db).initialize(sharingGroupUUID: sharingGroupUUID))
        doUpdateToNextMasterVersion(currentMasterVersion: 0, sharingGroupUUID: sharingGroupUUID)
        doUpdateToNextMasterVersion(currentMasterVersion: 1, sharingGroupUUID: sharingGroupUUID)
        checkMasterVersion(sharingGroupUUID: sharingGroupUUID, version: 2)
    }
    
    func testUpdateToNextFailsWithWrongExpectedMasterVersion() {
        let sharingGroupUUID = UUID().uuidString
        guard case .success = SharingGroupRepository(db).add(sharingGroupUUID: sharingGroupUUID) else {
            XCTFail()
            return
        }
        
        XCTAssert(MasterVersionRepository(db).initialize(sharingGroupUUID: sharingGroupUUID))
        doUpdateToNextMasterVersion(currentMasterVersion: 1, sharingGroupUUID: sharingGroupUUID, expectedError: true)
    }
    
    func lockIt(lock:Lock, removeStale:Bool = true) -> Bool {
        if case .success = LockRepository(db).lock(lock: lock, removeStale:removeStale) {
            return true
        }
        else {
            return false
        }
    }
    
    func testLock() {
        let sharingGroupUUID = UUID().uuidString
        guard case .success = SharingGroupRepository(db).add(sharingGroupUUID: sharingGroupUUID) else {
            XCTFail()
            return
        }
        
        let lock = Lock(sharingGroupUUID:sharingGroupUUID, deviceUUID:Foundation.UUID().uuidString)
        XCTAssert(lockIt(lock: lock))
        XCTAssert(!lockIt(lock: lock))
    }
    
    func testThatNewlyAddedLocksAreNotStale() {
        let sharingGroupUUID = UUID().uuidString
        guard case .success = SharingGroupRepository(db).add(sharingGroupUUID: sharingGroupUUID) else {
            XCTFail()
            return
        }
        
        let lock = Lock(sharingGroupUUID:sharingGroupUUID, deviceUUID:Foundation.UUID().uuidString)
        XCTAssert(lockIt(lock: lock))
        XCTAssert(LockRepository(db).removeStaleLock() == 0)
        XCTAssert(!lockIt(lock: lock))
    }
    
    func testThatStaleALockIsRemoved() {
        let sharingGroupUUID = UUID().uuidString
        guard case .success = SharingGroupRepository(db).add(sharingGroupUUID: sharingGroupUUID) else {
            XCTFail()
            return
        }
        
        let duration:TimeInterval = 1
        let lock = Lock(sharingGroupUUID:sharingGroupUUID, deviceUUID:Foundation.UUID().uuidString, expiryDuration:duration)
        XCTAssert(lockIt(lock: lock))
        
        let sleepDuration = UInt32(duration) + UInt32(1)
        sleep(sleepDuration)
        
        XCTAssert(LockRepository(db).removeStaleLock(forSharingGroupUUID: sharingGroupUUID) == 1)
        XCTAssert(lockIt(lock: lock, removeStale:false))
    }
    
    func testRemoveAllStaleLocks() {
        let sharingGroupUUID1 = UUID().uuidString
        guard case .success = SharingGroupRepository(db).add(sharingGroupUUID: sharingGroupUUID1) else {
            XCTFail()
            return
        }

        let sharingGroupUUID2 = UUID().uuidString
        guard case .success = SharingGroupRepository(db).add(sharingGroupUUID: sharingGroupUUID2) else {
            XCTFail()
            return
        }
        
        let duration:TimeInterval = 1
        
        let lock1 = Lock(sharingGroupUUID:sharingGroupUUID1, deviceUUID:Foundation.UUID().uuidString, expiryDuration:duration)
        XCTAssert(lockIt(lock: lock1))
        
        let lock2 = Lock(sharingGroupUUID:sharingGroupUUID2, deviceUUID:Foundation.UUID().uuidString, expiryDuration:duration)
        XCTAssert(lockIt(lock: lock2))
        
        let sleepDuration = UInt32(duration) + UInt32(1)
        sleep(sleepDuration)
        
        XCTAssert(LockRepository(db).removeStaleLock() == 2)
        
        XCTAssert(lockIt(lock: lock1, removeStale:false))
        XCTAssert(lockIt(lock: lock2, removeStale:false))
    }
    
    func testRemoveLock() {
        let sharingGroupUUID = UUID().uuidString
        
        guard case .success = SharingGroupRepository(db).add(sharingGroupUUID: sharingGroupUUID) else {
            XCTFail()
            return
        }
        
        let lock = Lock(sharingGroupUUID:sharingGroupUUID, deviceUUID:Foundation.UUID().uuidString)
        XCTAssert(lockIt(lock: lock))
        XCTAssert(LockRepository(db).unlock(sharingGroupUUID:sharingGroupUUID))
        XCTAssert(lockIt(lock: lock))
    }
    
    func doAddFileIndex(userId:UserId = 1, sharingGroupUUID:String, createSharingGroup: Bool) -> FileIndex? {

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
        
        guard let result1 = FileIndexRepository(db).add(fileIndex: fileIndex) else {
            XCTFail()
            return nil
        }

        fileIndex.fileIndexId = result1
        
        return fileIndex
    }
    
    func testAddFileIndex() {
        let user1 = User()
        user1.username = "Chris"
        user1.accountType = .Google
        user1.creds = "{\"accessToken\": \"SomeAccessTokenValue1\"}"
        user1.credsId = "100"
        
        guard let userId = UserRepository(db).add(user: user1) else {
            XCTFail("Bad credentialsId!")
            return
        }
        
        let sharingGroupUUID = UUID().uuidString
        guard let _ = doAddFileIndex(userId:userId, sharingGroupUUID: sharingGroupUUID, createSharingGroup: true) else {
            XCTFail()
            return
        }
    }
    
    func testUpdateFileIndexWithNoChanges() {
        let user1 = User()
        user1.username = "Chris"
        user1.accountType = .Google
        user1.creds = "{\"accessToken\": \"SomeAccessTokenValue1\"}"
        user1.credsId = "100"
        
        guard let userId = UserRepository(db).add(user: user1) else {
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
        user1.accountType = .Google
        user1.creds = "{\"accessToken\": \"SomeAccessTokenValue1\"}"
        user1.credsId = "100"
        let sharingGroupUUID = UUID().uuidString

        guard let userId = UserRepository(db).add(user: user1) else {
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
        user1.accountType = .Google
        user1.creds = "{\"accessToken\": \"SomeAccessTokenValue1\"}"
        user1.credsId = "100"
        let sharingGroupUUID = UUID().uuidString

        guard let userId = UserRepository(db).add(user: user1) else {
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
        user1.accountType = .Google
        user1.creds = "{\"accessToken\": \"SomeAccessTokenValue1\"}"
        user1.credsId = "100"
        let sharingGroupUUID = UUID().uuidString

        guard let userId = UserRepository(db).add(user: user1) else {
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
        user1.accountType = .Google
        user1.creds = "{\"accessToken\": \"SomeAccessTokenValue1\"}"
        user1.credsId = "100"
        let sharingGroupUUID = UUID().uuidString

        guard let userId = UserRepository(db).add(user: user1) else {
            XCTFail("Bad credentialsId!")
            return
        }
        
        guard let fileIndex1 = doAddFileIndex(userId:userId, sharingGroupUUID: sharingGroupUUID, createSharingGroup: true) else {
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

        case .noObjectFound:
            XCTFail("No Upload Found")
        }
    }
    
    func testFileIndexWithNoFiles() {
        let user1 = User()
        user1.username = "Chris"
        user1.accountType = .Google
        user1.creds = "{\"accessToken\": \"SomeAccessTokenValue1\"}"
        user1.credsId = "100"
        let sharingGroupUUID = UUID().uuidString

        guard let userId = UserRepository(db).add(user: user1) else {
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
        user1.accountType = .Google
        user1.creds = "{\"accessToken\": \"SomeAccessTokenValue1\"}"
        user1.credsId = "100"
        let sharingGroupUUID = UUID().uuidString

        guard let userId = UserRepository(db).add(user: user1) else {
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
            XCTAssert(fileIndex[0].cloudStorageType == CloudStorageType.Google.rawValue)
            
        case .error(_):
            XCTFail()
        }
    }
    
    func doAddDeviceUUID(userId:UserId = 1, repo:DeviceUUIDRepository) -> DeviceUUID? {
        let du = DeviceUUID(userId: userId, deviceUUID: Foundation.UUID().uuidString)
        let result = repo.add(deviceUUID: du)
        
        switch result {
        case .error(_), .exceededMaximumUUIDsPerUser:
            return nil
        case .success:
            return du
        }
    }
    
    func testAddDeviceUUID() {
        XCTAssert(doAddDeviceUUID(repo:DeviceUUIDRepository(db)) != nil)
    }
    
    func testAddDeviceUUIDFailsAfterMax() {
        let repo = DeviceUUIDRepository(db)
        let number = repo.maximumNumberOfDeviceUUIDsPerUser! + 1
        for curr in 1...number {
            if curr < number {
                XCTAssert(doAddDeviceUUID(repo: repo) != nil)
            }
            else {
                XCTAssert(doAddDeviceUUID(repo: repo) == nil)
            }
        }
    }
    
    func testAddDeviceUUIDDoesNotFailFailsAfterMaxWithNilMax() {
        let repo = DeviceUUIDRepository(db)
        let number = repo.maximumNumberOfDeviceUUIDsPerUser! + 1
        repo.maximumNumberOfDeviceUUIDsPerUser = nil
        
        for _ in 1...number {
            XCTAssert(doAddDeviceUUID(repo: repo) != nil)
        }
    }
    
    func testLookupFromDeviceUUID() {
        let repo = DeviceUUIDRepository(db)
        let result = doAddDeviceUUID(repo:repo)
        XCTAssert(result != nil)
        let key = DeviceUUIDRepository.LookupKey.deviceUUID(result!.deviceUUID)
        let lookupResult = repo.lookup(key: key, modelInit: DeviceUUID.init)
        
        if case .found(let model) = lookupResult,
            let du = model as? DeviceUUID {
            XCTAssert(du.deviceUUID == result!.deviceUUID)
            XCTAssert(du.userId == result!.userId)
        }
        else {
            XCTFail()
        }
    }
}

extension SpecificDatabaseTests {
    static var allTests : [(String, (SpecificDatabaseTests) -> () throws -> Void)] {
        return [
            ("testUpdateToNextMasterVersion", testUpdateToNextMasterVersion),
            ("testUpdateToNextTwiceMasterVersion", testUpdateToNextTwiceMasterVersion),
            ("testUpdateToNextFailsWithWrongExpectedMasterVersion", testUpdateToNextFailsWithWrongExpectedMasterVersion),
            ("testLock", testLock),
            ("testThatNewlyAddedLocksAreNotStale", testThatNewlyAddedLocksAreNotStale),
            ("testThatStaleALockIsRemoved", testThatStaleALockIsRemoved),
            ("testRemoveAllStaleLocks", testRemoveAllStaleLocks),
            ("testRemoveLock", testRemoveLock),
            ("testAddFileIndex", testAddFileIndex),
            ("testUpdateFileIndexWithNoChanges", testUpdateFileIndexWithNoChanges),
            ("testUpdateFileIndexWithAChange", testUpdateFileIndexWithAChange),
            ("testUpdateFileIndexFailsWithoutFileIndexId", testUpdateFileIndexFailsWithoutFileIndexId),
            ("testUpdateUploadSucceedsWithNilAppMetaData", testUpdateUploadSucceedsWithNilAppMetaData),
            ("testLookupFromFileIndex", testLookupFromFileIndex),
            ("testFileIndexWithNoFiles", testFileIndexWithNoFiles),
            ("testFileIndexWithOneFile", testFileIndexWithOneFile),
            ("testAddDeviceUUID", testAddDeviceUUID),
            ("testAddDeviceUUIDFailsAfterMax", testAddDeviceUUIDFailsAfterMax),
            ("testAddDeviceUUIDDoesNotFailFailsAfterMaxWithNilMax", testAddDeviceUUIDDoesNotFailFailsAfterMaxWithNilMax),
            ("testLookupFromDeviceUUID", testLookupFromDeviceUUID)
        ]
    }
    
    func testLinuxTestSuiteIncludesAllTests() {
        linuxTestSuiteIncludesAllTests(testType: SpecificDatabaseTests.self)
    }
}
