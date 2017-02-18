//
//  SepecificDatabaseTests.swift
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
import PerfectLib

class SepecificDatabaseTests: ServerTestCase {

    override func setUp() {
        super.setUp()
        _ = UserRepository(db).remove()
        _ = UserRepository(db).create()
        _ = UploadRepository(db).remove()
        _ = UploadRepository(db).create()
        _ = MasterVersionRepository(db).remove()
        _ = MasterVersionRepository(db).create()
        _ = LockRepository(db).remove()
        _ = LockRepository(db).create()
        _ = FileIndexRepository(db).remove()
        _ = FileIndexRepository(db).create()
        _ = DeviceUUIDRepository(db).remove()
        _ = DeviceUUIDRepository(db).create()
    }
    
    override func tearDown() {
        super.tearDown()
    }
    
    func testAddUser() {
        let user1 = User()
        user1.username = "Chris"
        user1.accountType = .Google
        user1.creds = "{\"accessToken\": \"SomeAccessTokenValue1\"}"
        user1.credsId = "100"
        
        let result1 = UserRepository(db).add(user: user1)
        XCTAssert(result1 == 1, "Bad credentialsId!")

        let user2 = User()
        user2.username = "Natasha"
        user2.accountType = .Google
        user2.creds = "{\"accessToken\": \"SomeAccessTokenValue2\"}"
        user2.credsId = "200"
        
        let result2 = UserRepository(db).add(user: user2)
        XCTAssert(result2 == 2, "Bad credentialsId!")
    }
    
    func testUserLookup1() {
        testAddUser()
        
        let result = UserRepository(db).lookup(key: .userId(1), modelInit:User.init)
        switch result {
        case .error(let error):
            XCTFail("\(error)")
            
        case .found(let object):
            let user = object as! User
            XCTAssert(user.accountType == .Google)
            XCTAssert(user.username == "Chris")
            XCTAssert(user.creds == "{\"accessToken\": \"SomeAccessTokenValue1\"}")
            XCTAssert(user.userId == 1)
            
        case .noObjectFound:
            XCTFail("No User Found")
        }
    }
    
    func testUserLookup1b() {
        testAddUser()
        
        let result = UserRepository(db).lookup(key: .userId(1), modelInit: User.init)
        switch result {
        case .error(let error):
            XCTFail("\(error)")
            
        case .found(let object):
            let user = object as! User
            XCTAssert(user.accountType == .Google)
            XCTAssert(user.username == "Chris")
            XCTAssert(user.creds == "{\"accessToken\": \"SomeAccessTokenValue1\"}")
            XCTAssert(user.userId == 1)
            
        case .noObjectFound:
            XCTFail("No User Found")
        }
    }
    
    func testUserLookup2() {
        testAddUser()
        
        let result = UserRepository(db).lookup(key: .accountTypeInfo(accountType:.Google, credsId:"100"), modelInit:User.init)
        switch result {
        case .error(let error):
            XCTFail("\(error)")
            
        case .found(let object):
            let user = object as! User
            XCTAssert(user.accountType == .Google)
            XCTAssert(user.username == "Chris")
            XCTAssert(user.creds == "{\"accessToken\": \"SomeAccessTokenValue1\"}")
            XCTAssert(user.userId == 1)
            guard let credsObject = user.credsObject as? GoogleCreds else {
                XCTFail()
                return
            }
            
            XCTAssert(credsObject.accessToken == "SomeAccessTokenValue1")
            
        case .noObjectFound:
            XCTFail("No User Found")
        }
    }
    
    func doAddUpload(fileSizeBytes:Int64?=100) -> Upload {
        let upload = Upload()
        upload.deviceUUID = PerfectLib.UUID().string
        upload.fileSizeBytes = fileSizeBytes
        upload.fileUpload = true
        upload.fileUUID = PerfectLib.UUID().string
        upload.fileVersion = 1
        upload.mimeType = "text/plain"
        upload.state = .uploaded
        upload.userId = 1
        upload.appMetaData = "{ \"foo\": \"bar\" }"
        
        let result1 = UploadRepository(db).add(upload: upload)
        XCTAssert(result1 == 1, "Bad uploadId!")
        
        upload.uploadId = result1
        
        return upload
    }
    
    func testAddUpload() {
        _ = doAddUpload()
    }
    
    func testAddUploadSucceedsWithNilFileSizeBytes() {
        _ = doAddUpload(fileSizeBytes:nil)
    }
    
    func testUpdateUpload() {
        let upload = doAddUpload()
        XCTAssert(UploadRepository(db).update(upload: upload))
    }
    
    func testUpdateUploadFailsWithoutUploadId() {
        let upload = doAddUpload()
        upload.uploadId = nil
        XCTAssert(!UploadRepository(db).update(upload: upload))
    }
    
    func testUpdateUploadSucceedsWithNilFileSize() {
        let upload = doAddUpload()
        upload.fileSizeBytes = nil
        XCTAssert(UploadRepository(db).update(upload: upload))
    }
    
    func testLookupFromUpload() {
        let upload1 = doAddUpload()
        
        let result = UploadRepository(db).lookup(key: .uploadId(1), modelInit: Upload.init)
        switch result {
        case .error(let error):
            XCTFail("\(error)")
            
        case .found(let object):
            let upload2 = object as! Upload
            XCTAssert(upload1.deviceUUID != nil && upload1.deviceUUID == upload2.deviceUUID)
            XCTAssert(upload1.fileSizeBytes != nil && upload1.fileSizeBytes == upload2.fileSizeBytes)
            XCTAssert(upload1.fileUpload != nil && upload1.fileUpload == upload2.fileUpload)
            XCTAssert(upload1.fileUUID != nil && upload1.fileUUID == upload2.fileUUID)
            XCTAssert(upload1.fileVersion != nil && upload1.fileVersion == upload2.fileVersion)
            XCTAssert(upload1.mimeType != nil && upload1.mimeType == upload2.mimeType)
            XCTAssert(upload1.state != nil && upload1.state == upload2.state)
            XCTAssert(upload1.userId != nil && upload1.userId == upload2.userId)
            XCTAssert(upload1.appMetaData != nil && upload1.appMetaData == upload2.appMetaData)

        case .noObjectFound:
            XCTFail("No Upload Found")
        }
    }
    
    func checkMasterVersion(userId:UserId, version:Int64) {
        let result = MasterVersionRepository(db).lookup(key: .userId(userId), modelInit: MasterVersion.init)
        switch result {
        case .error(let error):
            XCTFail("\(error)")
            
        case .found(let object):
            let masterVersion = object as! MasterVersion
            XCTAssert(masterVersion.masterVersion == version && masterVersion.userId == userId)

        case .noObjectFound:
            XCTFail("No MasterVersion Found")
        }
    }
    
    let userId:UserId = 1

    func doUpdateToNextMasterVersion(currentMasterVersion:MasterVersionInt, expectedError: Bool = false) {
        
        let current = MasterVersion()
        current.userId = userId
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
        XCTAssert(MasterVersionRepository(db).initialize(userId: userId))
        doUpdateToNextMasterVersion(currentMasterVersion: 0)
        checkMasterVersion(userId: userId, version: 1)
    }

    func testUpdateToNextTwiceMasterVersion() {
        XCTAssert(MasterVersionRepository(db).initialize(userId: userId))
        doUpdateToNextMasterVersion(currentMasterVersion: 0)
        doUpdateToNextMasterVersion(currentMasterVersion: 1)
        checkMasterVersion(userId: userId, version: 2)
    }
    
    func testUpdateToNextFailsWithWrongExpectedMasterVersion() {
        XCTAssert(MasterVersionRepository(db).initialize(userId: userId))
        doUpdateToNextMasterVersion(currentMasterVersion: 1, expectedError: true)
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
        let lock = Lock(userId:1, deviceUUID:PerfectLib.UUID().string)
        XCTAssert(lockIt(lock: lock))
        XCTAssert(!lockIt(lock: lock))
    }
    
    func testThatNewlyAddedLocksAreNotStale() {
        let lock = Lock(userId:1, deviceUUID:PerfectLib.UUID().string)
        XCTAssert(lockIt(lock: lock))
        XCTAssert(LockRepository(db).removeStaleLock(forUserId: 1) == 0)
        XCTAssert(!lockIt(lock: lock))
    }
    
    func testThatStaleALockIsRemoved() {
        let duration:TimeInterval = 1
        let lock = Lock(userId:1, deviceUUID:PerfectLib.UUID().string, expiryDuration:duration)
        XCTAssert(lockIt(lock: lock))
        
        let sleepDuration = UInt32(duration) + UInt32(1)
        sleep(sleepDuration)
        
        XCTAssert(LockRepository(db).removeStaleLock(forUserId: 1) == 1)
        XCTAssert(lockIt(lock: lock, removeStale:false))
    }
    
    func testRemoveAllStaleLocks() {
        let duration:TimeInterval = 1
        
        let lock1 = Lock(userId:1, deviceUUID:PerfectLib.UUID().string, expiryDuration:duration)
        XCTAssert(lockIt(lock: lock1))
        
        let lock2 = Lock(userId:2, deviceUUID:PerfectLib.UUID().string, expiryDuration:duration)
        XCTAssert(lockIt(lock: lock2))
        
        let sleepDuration = UInt32(duration) + UInt32(1)
        sleep(sleepDuration)
        
        XCTAssert(LockRepository(db).removeStaleLock() == 2)
        
        XCTAssert(lockIt(lock: lock1, removeStale:false))
        XCTAssert(lockIt(lock: lock2, removeStale:false))
    }
    
    func testRemoveLock() {
        let lock = Lock(userId:1, deviceUUID:PerfectLib.UUID().string)
        XCTAssert(lockIt(lock: lock))
        XCTAssert(LockRepository(db).unlock(userId:1))
        XCTAssert(lockIt(lock: lock))
    }
    
    func doAddFileIndex(userId:UserId = 1) -> FileIndex {
        let fileIndex = FileIndex()
        fileIndex.fileSizeBytes = 100
        fileIndex.deleted = false
        fileIndex.fileUUID = PerfectLib.UUID().string
        fileIndex.deviceUUID = PerfectLib.UUID().string
        fileIndex.fileVersion = 1
        fileIndex.mimeType = "text/plain"
        fileIndex.userId = userId
        fileIndex.appMetaData = "{ \"foo\": \"bar\" }"
        
        let result1 = FileIndexRepository(db).add(fileIndex: fileIndex)
        XCTAssert(result1 == 1, "Bad fileIndexId!")
        fileIndex.fileIndexId = result1
        
        return fileIndex
    }
    
    func testAddFileIndex() {
        _ = doAddFileIndex()
    }
    
    func testUpdateFileIndexWithNoChanges() {
        let fileIndex = doAddFileIndex()
        XCTAssert(FileIndexRepository(db).update(fileIndex: fileIndex))
    }
    
    func testUpdateFileIndexWithAChange() {
        let fileIndex = doAddFileIndex()
        fileIndex.fileVersion = 2
        XCTAssert(FileIndexRepository(db).update(fileIndex: fileIndex))
    }
    
    func testUpdateFileIndexFailsWithoutFileIndexId() {
        let fileIndex = doAddFileIndex()
        fileIndex.fileIndexId = nil
        XCTAssert(!FileIndexRepository(db).update(fileIndex: fileIndex))
    }
    
    func testUpdateUploadSucceedsWithNilAppMetaData() {
        let fileIndex = doAddFileIndex()
        fileIndex.appMetaData = nil
        XCTAssert(FileIndexRepository(db).update(fileIndex: fileIndex))
    }
    
    func testLookupFromFileIndex() {
        let fileIndex1 = doAddFileIndex()
        
        let result = FileIndexRepository(db).lookup(key: .fileIndexId(1), modelInit: FileIndex.init)
        switch result {
        case .error(let error):
            XCTFail("\(error)")
            
        case .found(let object):
            let fileIndex2 = object as! FileIndex
            XCTAssert(fileIndex1.fileSizeBytes != nil && fileIndex1.fileSizeBytes == fileIndex2.fileSizeBytes)
            XCTAssert(fileIndex1.deleted != nil && fileIndex1.deleted == fileIndex2.deleted)
            XCTAssert(fileIndex1.fileUUID != nil && fileIndex1.fileUUID == fileIndex2.fileUUID)
            XCTAssert(fileIndex1.deviceUUID != nil && fileIndex1.deviceUUID == fileIndex2.deviceUUID)

            XCTAssert(fileIndex1.fileVersion != nil && fileIndex1.fileVersion == fileIndex2.fileVersion)
            XCTAssert(fileIndex1.mimeType != nil && fileIndex1.mimeType == fileIndex2.mimeType)
            XCTAssert(fileIndex1.userId != nil && fileIndex1.userId == fileIndex2.userId)
            XCTAssert(fileIndex1.appMetaData != nil && fileIndex1.appMetaData == fileIndex2.appMetaData)

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
        
        let result1 = UserRepository(db).add(user: user1)
        XCTAssert(result1 == 1, "Bad credentialsId!")
        
        let fileIndexResult = FileIndexRepository(db).fileIndex(forUserId: result1!)
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
        
        let userId = UserRepository(db).add(user: user1)
        XCTAssert(userId == 1, "Bad credentialsId!")
        
        let fileIndexInserted = doAddFileIndex(userId: userId!)

        let fileIndexResult = FileIndexRepository(db).fileIndex(forUserId: userId!)
        switch fileIndexResult {
        case .fileIndex(let fileIndex):
            XCTAssert(fileIndex.count == 1)
            XCTAssert(fileIndexInserted.appMetaData == fileIndex[0].appMetaData)
            XCTAssert(fileIndexInserted.fileUUID == fileIndex[0].fileUUID)
            XCTAssert(fileIndexInserted.fileVersion == fileIndex[0].fileVersion)
            XCTAssert(fileIndexInserted.mimeType == fileIndex[0].mimeType)
            XCTAssert(fileIndexInserted.deleted == fileIndex[0].deleted)
            XCTAssert(fileIndexInserted.fileSizeBytes == fileIndex[0].fileSizeBytes)
        case .error(_):
            XCTFail()
        }
    }
    
    func doAddDeviceUUID(userId:UserId = 1, repo:DeviceUUIDRepository) -> DeviceUUID? {
        let du = DeviceUUID(userId: userId, deviceUUID: PerfectLib.UUID().string)
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
