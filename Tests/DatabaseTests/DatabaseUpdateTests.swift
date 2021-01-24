
import XCTest
@testable import Server
@testable import TestsCommon
import LoggerAPI
import HeliumLogger
import Foundation
import ServerShared

class DatabaseUpdateTests: ServerTestCase {
    var accountManager: AccountManager!
    var userRepo: UserRepository!

    // Just an example repo
    var fileIndexRepo: FileIndexRepository!
    var exampleUserId: UserId!

    let sharingGroupUUID = UUID().uuidString

    override func setUp() {
        super.setUp()
        userRepo = UserRepository(db)
        accountManager = AccountManager()
        
        let user1 = User()
        user1.username = "Chris"
        user1.accountType = AccountScheme.google.accountName
        user1.creds = "{\"accessToken\": \"SomeAccessTokenValue1\"}"
        user1.credsId = "100"
        
        let accountDelegate = UserRepository.AccountDelegateHandler(userRepository: userRepo, accountManager: accountManager)
        guard let userId = userRepo.add(user: user1, accountManager: accountManager, accountDelegate: accountDelegate, validateJSON: false) else {
            XCTFail("Bad credentialsId!")
            return
        }
        
        exampleUserId = userId
        
        fileIndexRepo = FileIndexRepository(db)
    }
    
    @discardableResult
    func runUpdateSingleField(fieldName: String, valueType: Database.PreparedStatement.ValueType, expectedUpdateResult: Bool) throws -> FileIndex? {

        // Add an extra-- so we can search for update and have it be meaningful.
        guard let _ = doAddFileIndex(userId:exampleUserId, sharingGroupUUID: sharingGroupUUID, createSharingGroup: true) else {
            XCTFail()
            return nil
        }
        
        guard let fileIndex = doAddFileIndex(userId:exampleUserId, sharingGroupUUID: sharingGroupUUID, createSharingGroup: false) else {
            XCTFail()
            return nil
        }
    
        let result = fileIndexRepo.update(indexId: fileIndex.fileIndexId, with: [
            fieldName: valueType
        ])
        
        XCTAssertTrue(result == expectedUpdateResult)
        let key = FileIndexRepository.LookupKey.fileIndexId(fileIndex.fileIndexId)
        let result2 = fileIndexRepo.lookup(key: key, modelInit: FileIndex.init)
        guard case .found(let model) = result2, let fileIndex2 = model as? FileIndex else {
            XCTFail()
            return nil
        }
        
        return fileIndex2
    }
    
    func testUpdateExistingSingleFieldWorks() throws {
        guard let result = try runUpdateSingleField(fieldName: FileIndex.fileVersionKey, valueType: .int32(0), expectedUpdateResult: true) else {
            XCTFail()
            return
        }
        
        XCTAssertTrue(result.fileVersion == 0)
    }
    
    func testUpdateNonExistingSingleFieldFails() throws {
        try runUpdateSingleField(fieldName: "Foobly", valueType: .int32(0), expectedUpdateResult: false)
    }
    
    func testUpdateMultipleFieldsWorks() throws {
        // Add an extra-- so we can search for update and have it be meaningful.
        guard let _ = doAddFileIndex(userId:exampleUserId, sharingGroupUUID: sharingGroupUUID, createSharingGroup: true) else {
            XCTFail()
            return
        }
        
        guard let fileIndex = doAddFileIndex(userId:exampleUserId, sharingGroupUUID: sharingGroupUUID, createSharingGroup: false) else {
            XCTFail()
            return
        }
    
        let newFileVersion: FileVersionInt = 67
        
        let result = fileIndexRepo.update(indexId: fileIndex.fileIndexId, with: [
            FileIndex.fileVersionKey: .int32(newFileVersion),
            FileIndex.deletedKey: .bool(true)
        ])
        
        XCTAssertTrue(result)
        
        let key = FileIndexRepository.LookupKey.fileIndexId(fileIndex.fileIndexId)
        let result2 = fileIndexRepo.lookup(key: key, modelInit: FileIndex.init)
        guard case .found(let model) = result2, let fileIndex2 = model as? FileIndex else {
            XCTFail()
            return
        }
        
        XCTAssertTrue(fileIndex.fileIndexId == fileIndex2.fileIndexId)
        XCTAssertTrue(fileIndex2.fileVersion == newFileVersion)
        XCTAssertTrue(fileIndex2.deleted == true)
    }
    
    func testUpdateAll() {
        guard let _ = doAddFileIndex(userId:exampleUserId, sharingGroupUUID: sharingGroupUUID, createSharingGroup: true) else {
            XCTFail()
            return
        }
        
        guard let _ = doAddFileIndex(userId:exampleUserId, sharingGroupUUID: sharingGroupUUID, createSharingGroup: false) else {
            XCTFail()
            return
        }
        
        let newVersion = FileVersionInt(87)
        
        let key = FileIndexRepository.LookupKey.sharingGroupUUID(sharingGroupUUID: sharingGroupUUID)
        let result = fileIndexRepo.updateAll(key: key, updates: [FileIndex.fileVersionKey : .int32(newVersion)])
        XCTAssert(result == 2)
        
        guard let records = fileIndexRepo.lookupAll(key: key, modelInit: FileIndex.init), records.count == 2 else {
            XCTFail()
            return
        }
        
        for record in records {
            XCTAssert(record.fileVersion == newVersion)
        }
    }
}
