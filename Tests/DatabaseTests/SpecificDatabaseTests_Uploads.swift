//
//  SpecificDatabaseTests_Uploads.swift
//  Server
//
//  Created by Christopher Prince on 2/18/17.
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
import ServerAccount

class SpecificDatabaseTests_Uploads: ServerTestCase {
    var accountDelegate: AccountDelegate!
    
    override func setUp() {
        super.setUp()
        if case .failure = UploadRepository(db).upcreate() {
            XCTFail()
        }
        
        let userRepo = UserRepository(db)
        let accountManager = AccountManager()
        accountDelegate = UserRepository.AccountDelegateHandler(userRepository: userRepo, accountManager: accountManager)
    }
    
    override func tearDown() {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
        super.tearDown()
    }

    func doAddUpload(sharingGroupUUID: String, checkSum: String? = "", uploadContents: Data? = nil, changeResolverName: String? = "ExampleChangeResolver", uploadIndex: Int32 = 1, uploadCount: Int32 = 1, mimeType:String? = "text/plain", appMetaData:AppMetaData? = AppMetaData(contents: "{ \"foo\": \"bar\" }"), userId:UserId = 1, deviceUUID:String = Foundation.UUID().uuidString, deferredUploadId: Int64? = nil, fileVersion: FileVersionInt = 0, missingField:Bool = false, expectError: Bool = false) -> Upload {
        let upload = Upload()
        
        if !missingField {
            upload.deviceUUID = deviceUUID
        }
        
        upload.lastUploadedCheckSum = checkSum
        upload.fileUUID = Foundation.UUID().uuidString
        upload.fileVersion = fileVersion
        upload.mimeType = mimeType
        upload.state = fileVersion == 0 ? .v0UploadCompleteFile : .vNUploadFileChange
        upload.userId = userId
        upload.appMetaData = appMetaData?.contents
        upload.creationDate = Date()
        upload.updateDate = Date()
        upload.sharingGroupUUID = sharingGroupUUID
        upload.uploadContents = uploadContents
        upload.uploadCount = uploadCount
        upload.uploadIndex = uploadIndex
        upload.deferredUploadId = deferredUploadId
        if fileVersion == 0 {
            upload.changeResolverName = changeResolverName
        }
        
        let result = UploadRepository(db).add(upload: upload)
        
        var uploadId:Int64?
        switch result {
        case .success(uploadId: let id):
            XCTAssertTrue(!expectError)
            if missingField {
                XCTFail()
            }
            uploadId = id
        
        default:
            XCTAssertTrue(expectError)
            if !expectError {
                if !missingField {
                    XCTFail()
                }
            }
        }
        
        upload.uploadId = uploadId
        
        return upload
    }
    
    func testAddSingleUpload() {
        let sharingGroupUUID = UUID().uuidString
        guard case .success = SharingGroupRepository(db).add(sharingGroupUUID: sharingGroupUUID) else {
            XCTFail()
            return
        }
        
        _ = doAddUpload(sharingGroupUUID:sharingGroupUUID)
    }
    
    func testAddUploadWithMissingField() {
        let sharingGroupUUID = UUID().uuidString
        guard case .success = SharingGroupRepository(db).add(sharingGroupUUID: sharingGroupUUID) else {
            XCTFail()
            return
        }
        
        _ = doAddUpload(sharingGroupUUID:sharingGroupUUID, missingField: true, expectError: true)
    }
    
    func doAddUploadDeletion(sharingGroupUUID: String, userId:UserId = 1, deviceUUID:String = Foundation.UUID().uuidString, missingField:Bool = false) -> Upload {
        let upload = Upload()
        upload.deviceUUID = deviceUUID
        upload.fileUUID = Foundation.UUID().uuidString
        upload.fileVersion = 1
        upload.state = .deleteSingleFile
        upload.sharingGroupUUID = sharingGroupUUID
        upload.uploadIndex = 1
        upload.uploadCount = 1
        
        if !missingField {
            upload.userId = userId
        }
        
        let result = UploadRepository(db).add(upload: upload)
        
        var uploadId:Int64?
        switch result {
        case .success(uploadId: let id):
            if missingField {
                XCTFail()
            }
            uploadId = id
        
        default:
            if !missingField {
                XCTFail()
            }
        }
        
        if missingField {
            XCTAssert(uploadId == nil, "Good uploadId!")
        }
        else {
            XCTAssert(uploadId == 1, "Bad uploadId!")
            upload.uploadId = uploadId
        }
        
        return upload
    }
    
    func testAddUploadDeletion() {
        let sharingGroupUUID = UUID().uuidString

        guard case .success = SharingGroupRepository(db).add(sharingGroupUUID: sharingGroupUUID) else {
            XCTFail()
            return
        }
        
        _ = doAddUploadDeletion(sharingGroupUUID:sharingGroupUUID)
    }
    
    func testAddUploadDeletionWithMissingField() {
        let sharingGroupUUID = UUID().uuidString

        guard case .success = SharingGroupRepository(db).add(sharingGroupUUID: sharingGroupUUID) else {
            XCTFail()
            return
        }
        
        _ = doAddUploadDeletion(sharingGroupUUID:sharingGroupUUID, missingField:true)
    }
    
    func testAddUploadSucceedsWithNilAppMetaData() {
        let sharingGroupUUID = UUID().uuidString
        guard case .success = SharingGroupRepository(db).add(sharingGroupUUID: sharingGroupUUID) else {
            XCTFail()
            return
        }
        
        _ = doAddUpload(sharingGroupUUID:sharingGroupUUID, appMetaData:nil)
    }
    
    func testAddUploadSucceedsWithNilCheckSumWhenFileVersionGreaterThanZero() {
        let sharingGroupUUID = UUID().uuidString
        guard case .success = SharingGroupRepository(db).add(sharingGroupUUID: sharingGroupUUID) else {
            XCTFail()
            return
        }
        
        _ = doAddUpload(sharingGroupUUID:sharingGroupUUID, checkSum:nil, changeResolverName: nil,  fileVersion: 1)
    }
    
    func testAddUploadFailsWithNilCheckSumWhenFileVersionIsZero() {
        let sharingGroupUUID = UUID().uuidString
        guard case .success = SharingGroupRepository(db).add(sharingGroupUUID: sharingGroupUUID) else {
            XCTFail()
            return
        }
        
        _ = doAddUpload(sharingGroupUUID:sharingGroupUUID, checkSum:nil, fileVersion: 0, expectError: true)
    }
    
    func testUpdateUpload() {
        let sharingGroupUUID = UUID().uuidString
        guard case .success = SharingGroupRepository(db).add(sharingGroupUUID: sharingGroupUUID) else {
            XCTFail()
            return
        }
        
        let upload = doAddUpload(sharingGroupUUID:sharingGroupUUID)
        XCTAssert(UploadRepository(db).update(upload: upload))
    }

    func testUpdateUploadWithDeferredUploadId() {
        let sharingGroupUUID = UUID().uuidString
        guard case .success = SharingGroupRepository(db).add(sharingGroupUUID: sharingGroupUUID) else {
            XCTFail()
            return
        }
        
        let upload = doAddUpload(sharingGroupUUID:sharingGroupUUID)
        upload.deferredUploadId = 101
        XCTAssert(UploadRepository(db).update(upload: upload))
    }
    
    func testUpdateUploadFailsWithoutUploadId() {
        let sharingGroupUUID = UUID().uuidString
        guard case .success = SharingGroupRepository(db).add(sharingGroupUUID: sharingGroupUUID) else {
            XCTFail()
            return
        }
        
        let upload = doAddUpload(sharingGroupUUID:sharingGroupUUID)
        upload.uploadId = nil
        XCTAssert(!UploadRepository(db).update(upload: upload))
    }
    
    func testUpdateUploadToUploadedWithv0UploadFileVersionFailsWithoutCheckSum() {
        let sharingGroupUUID = UUID().uuidString
        guard case .success = SharingGroupRepository(db).add(sharingGroupUUID: sharingGroupUUID) else {
            XCTFail()
            return
        }
        
        let upload = doAddUpload(sharingGroupUUID:sharingGroupUUID)
        upload.lastUploadedCheckSum = nil
        upload.state = .v0UploadCompleteFile
        XCTAssert(!UploadRepository(db).update(upload: upload))
    }
    
    func testUpdateUploadSucceedsWithNilAppMetaData() {
        let sharingGroupUUID = UUID().uuidString
        guard case .success = SharingGroupRepository(db).add(sharingGroupUUID: sharingGroupUUID) else {
            XCTFail()
            return
        }
        
        let upload = doAddUpload(sharingGroupUUID:sharingGroupUUID)
        upload.appMetaData = nil
        XCTAssert(UploadRepository(db).update(upload: upload))
    }
    
    func testLookupFromUpload() {
        let sharingGroupUUID = UUID().uuidString
        guard case .success = SharingGroupRepository(db).add(sharingGroupUUID: sharingGroupUUID) else {
            XCTFail()
            return
        }
        
        let testContents = "Test contents".data(using: .utf8)
        let deferredUploadId: Int64 = 201
        let upload1 = doAddUpload(sharingGroupUUID:sharingGroupUUID, uploadContents: testContents, deferredUploadId: deferredUploadId)
        
        let result = UploadRepository(db).lookup(key: .uploadId(1), modelInit: Upload.init)
        switch result {
        case .error(let error):
            XCTFail("\(error)")
            
        case .found(let object):
            let upload2 = object as! Upload
            XCTAssert(upload1.deviceUUID != nil && upload1.deviceUUID == upload2.deviceUUID)
            XCTAssert(upload1.lastUploadedCheckSum != nil && upload1.lastUploadedCheckSum == upload2.lastUploadedCheckSum)
            XCTAssert(upload1.fileUUID != nil && upload1.fileUUID == upload2.fileUUID)
            XCTAssert(upload1.fileVersion != nil && upload1.fileVersion == upload2.fileVersion)
            XCTAssert(upload1.mimeType != nil && upload1.mimeType == upload2.mimeType)
            XCTAssert(upload1.state != nil && upload1.state == upload2.state)
            XCTAssert(upload1.userId != nil && upload1.userId == upload2.userId)
            XCTAssert(upload1.appMetaData != nil && upload1.appMetaData == upload2.appMetaData)
            XCTAssertEqual(testContents, upload2.uploadContents)
            XCTAssertEqual(deferredUploadId, upload2.deferredUploadId)
            
        case .noObjectFound:
            XCTFail("No Upload Found")
        }
    }
    
    func testGetUploadsWithNoFiles() {
        let userRepo = UserRepository(db)
        let accountManager = AccountManager()
        let user1 = User()
        user1.username = "Chris"
        user1.accountType = AccountScheme.google.accountName
        user1.creds = "{\"accessToken\": \"SomeAccessTokenValue1\"}"
        user1.credsId = "100"
        
        let result1 = userRepo.add(user: user1, accountManager: accountManager, accountDelegate: accountDelegate, validateJSON: false)
        XCTAssert(result1 == 1, "Bad credentialsId!")
        
        let uploadedFilesResult = UploadRepository(db).uploadedFiles(forUserId: result1!, sharingGroupUUID: UUID().uuidString, deviceUUID: Foundation.UUID().uuidString)
        switch uploadedFilesResult {
        case .uploads(let uploads):
            XCTAssert(uploads.count == 0)
        case .error(_):
            XCTFail()
        }
    }

    func testUploadedIndexWithOneFile() {
        let userRepo = UserRepository(db)
        let accountManager = AccountManager()
        let sharingGroupUUID = UUID().uuidString
        let user1 = User()
        user1.username = "Chris"
        user1.accountType = AccountScheme.google.accountName
        user1.creds = "{\"accessToken\": \"SomeAccessTokenValue1\"}"
        user1.credsId = "100"
        
        let userId = userRepo.add(user: user1, accountManager: accountManager, accountDelegate: accountDelegate, validateJSON: false)
        XCTAssert(userId == 1, "Bad credentialsId!")
        
        guard case .success = SharingGroupRepository(db).add(sharingGroupUUID: sharingGroupUUID) else {
            XCTFail()
            return
        }
        
        let deviceUUID = Foundation.UUID().uuidString
        let index: Int32 = 1
        let count: Int32 = 1
        let upload1 = doAddUpload(sharingGroupUUID:sharingGroupUUID, uploadIndex: index, uploadCount: count, userId:userId!, deviceUUID:deviceUUID)

        let uploadedFilesResult = UploadRepository(db).uploadedFiles(forUserId: userId!, sharingGroupUUID: sharingGroupUUID, deviceUUID: deviceUUID)
        switch uploadedFilesResult {
        case .uploads(let uploads):
            guard uploads.count == 1 else {
                XCTFail()
                return
            }
            
            XCTAssert(upload1.appMetaData == uploads[0].appMetaData)
            XCTAssert(upload1.fileUUID == uploads[0].fileUUID)
            XCTAssert(upload1.fileVersion == uploads[0].fileVersion)
            XCTAssert(upload1.mimeType == uploads[0].mimeType)
            XCTAssert(upload1.lastUploadedCheckSum == uploads[0].lastUploadedCheckSum)
            XCTAssert(uploads[0].uploadIndex == index)
            XCTAssert(uploads[0].uploadCount == count)

        case .error(_):
            XCTFail()
        }
    }

    func testUploadedIndexWithNonNilDeferredUploadId() {
        let userRepo = UserRepository(db)
        let accountManager = AccountManager()
        let sharingGroupUUID = UUID().uuidString
        let user1 = User()
        user1.username = "Chris"
        user1.accountType = AccountScheme.google.accountName
        user1.creds = "{\"accessToken\": \"SomeAccessTokenValue1\"}"
        user1.credsId = "100"
        
        let userId = userRepo.add(user: user1, accountManager: accountManager, accountDelegate: accountDelegate, validateJSON: false)
        XCTAssert(userId == 1, "Bad credentialsId!")
        
        guard case .success = SharingGroupRepository(db).add(sharingGroupUUID: sharingGroupUUID) else {
            XCTFail()
            return
        }
        
        let deviceUUID = Foundation.UUID().uuidString
        let index: Int32 = 1
        let count: Int32 = 1
        let changeResolverName = "ExampleChangeResolverName"
        let upload1 = doAddUpload(sharingGroupUUID:sharingGroupUUID, changeResolverName:changeResolverName, uploadIndex: index, uploadCount: count, userId:userId!, deviceUUID:deviceUUID)
        
        let uploadedFilesResult1 = UploadRepository(db).uploadedFiles(forUserId: userId!, sharingGroupUUID: sharingGroupUUID, deviceUUID: deviceUUID)
        switch uploadedFilesResult1 {
        case .uploads(let uploads):
            guard uploads.count == 1 else {
                XCTFail()
                return
            }
            
            XCTAssert(upload1.appMetaData == uploads[0].appMetaData)
            XCTAssert(upload1.fileUUID == uploads[0].fileUUID)
            XCTAssert(upload1.fileVersion == uploads[0].fileVersion)
            XCTAssert(upload1.mimeType == uploads[0].mimeType)
            XCTAssert(upload1.lastUploadedCheckSum == uploads[0].lastUploadedCheckSum)
            XCTAssert(uploads[0].uploadIndex == index)
            XCTAssert(uploads[0].uploadCount == count)
            XCTAssert(uploads[0].changeResolverName == changeResolverName)

        case .error(_):
            XCTFail()
        }
        
        let deferredUploadId:Int64 = 87
        upload1.deferredUploadId = deferredUploadId
        guard UploadRepository(db).update(upload: upload1) else {
            XCTFail()
            return
        }

        let uploadedFilesResult2 = UploadRepository(db).uploadedFiles(forUserId: userId!, sharingGroupUUID: sharingGroupUUID, deviceUUID: deviceUUID, deferredUploadIdNull: true)
        switch uploadedFilesResult2 {
        case .uploads(let uploads):
            guard uploads.count == 0 else {
                XCTFail()
                return
            }

        case .error(_):
            XCTFail()
        }
        
        let uploadedFilesResult3 = UploadRepository(db).uploadedFiles(forUserId: userId!, sharingGroupUUID: sharingGroupUUID, deviceUUID: deviceUUID, deferredUploadIdNull: false)
        switch uploadedFilesResult3 {
        case .uploads(let uploads):
            guard uploads.count == 1 else {
                XCTFail()
                return
            }

        case .error(_):
            XCTFail()
        }
    }
    
    func testUploadedIndexWithInterleavedSharingGroupFiles() {
        let sharingGroupUUID1 = UUID().uuidString
        let sharingGroupUUID2 = UUID().uuidString
        let userRepo = UserRepository(db)
        let accountManager = AccountManager()
        
        let user1 = User()
        user1.username = "Chris"
        user1.accountType = AccountScheme.google.accountName
        user1.creds = "{\"accessToken\": \"SomeAccessTokenValue1\"}"
        user1.credsId = "100"
        
        let userId = userRepo.add(user: user1, accountManager: accountManager, accountDelegate: accountDelegate, validateJSON: false)
        XCTAssert(userId == 1, "Bad credentialsId!")
        
        guard case .success = SharingGroupRepository(db).add(sharingGroupUUID: sharingGroupUUID1) else {
            XCTFail()
            return
        }
        
        guard case .success = SharingGroupRepository(db).add(sharingGroupUUID: sharingGroupUUID2) else {
            XCTFail()
            return
        }
        
        let deviceUUID = Foundation.UUID().uuidString
        let upload1 = doAddUpload(sharingGroupUUID:sharingGroupUUID1, userId:userId!, deviceUUID:deviceUUID)

        // This is illustrating an "interleaved" upload-- where a client could have uploaded a file to a different sharing group UUID before doing a DoneUploads.
        let _ = doAddUpload(sharingGroupUUID:sharingGroupUUID2, userId:userId!, deviceUUID:deviceUUID)
        
        let uploadedFilesResult = UploadRepository(db).uploadedFiles(forUserId: userId!, sharingGroupUUID: sharingGroupUUID1, deviceUUID: deviceUUID)
        switch uploadedFilesResult {
        case .uploads(let uploads):
            XCTAssert(uploads.count == 1)
            XCTAssert(upload1.appMetaData == uploads[0].appMetaData)
            XCTAssert(upload1.fileUUID == uploads[0].fileUUID)
            XCTAssert(upload1.fileVersion == uploads[0].fileVersion)
            XCTAssert(upload1.mimeType == uploads[0].mimeType)
            XCTAssert(upload1.lastUploadedCheckSum == uploads[0].lastUploadedCheckSum)
            XCTAssert(upload1.sharingGroupUUID == uploads[0].sharingGroupUUID)
        case .error(_):
            XCTFail()
        }
    }
    
    // MARK: select(forDeferredUploadIds
    
    func doAddDeferredUpload(userId: UserId, status: DeferredUploadStatus, sharingGroupUUID: String, fileGroupUUID: String? = nil) -> DeferredUpload? {
        let repo = DeferredUploadRepository(db)

        let deferredUpload = DeferredUpload()

        deferredUpload.status = status
        deferredUpload.fileGroupUUID = fileGroupUUID
        deferredUpload.sharingGroupUUID = sharingGroupUUID
        deferredUpload.userId = userId
        
        let result = repo.add(deferredUpload)
        
        var deferredUploadId:Int64?
        switch result {
        case .success(deferredUploadId: let id):
            deferredUploadId = id
        
        default:
            return nil
        }
        
        deferredUpload.deferredUploadId = deferredUploadId
        
        return deferredUpload
    }
    
    func testSelectForDeferredUploadIdsWithSingleUpload() {
        let uploadRepo = UploadRepository(db)
        
        let sharingGroupUUID = UUID().uuidString
        guard case .success = SharingGroupRepository(db).add(sharingGroupUUID: sharingGroupUUID) else {
            XCTFail()
            return
        }
        
        guard let deferredUpload = doAddDeferredUpload(userId: 1, status: .pendingChange, sharingGroupUUID: sharingGroupUUID),
            let deferredUploadId = deferredUpload.deferredUploadId else {
            XCTFail()
            return
        }
        
        let upload = doAddUpload(sharingGroupUUID:sharingGroupUUID, deferredUploadId: deferredUploadId)
        
        guard let uploadId = upload.uploadId else {
            XCTFail()
            return
        }
        
        guard let result = uploadRepo.select(forDeferredUploadIds: [deferredUploadId]),
            result.count == 1 else {
            XCTFail()
            return
        }
        
        XCTAssert(result[0].uploadId == uploadId)
    }
    
    func testSelectForDeferredUploadIdsWithTwoUploadsAndOneDeferredUpload() {
        let uploadRepo = UploadRepository(db)
        
        let sharingGroupUUID = UUID().uuidString
        guard case .success = SharingGroupRepository(db).add(sharingGroupUUID: sharingGroupUUID) else {
            XCTFail()
            return
        }
        
        guard let deferredUpload = doAddDeferredUpload(userId: 1, status: .pendingChange, sharingGroupUUID: sharingGroupUUID),
            let deferredUploadId = deferredUpload.deferredUploadId else {
            XCTFail()
            return
        }
        
        let upload1 = doAddUpload(sharingGroupUUID:sharingGroupUUID, deferredUploadId: deferredUploadId)
        let upload2 = doAddUpload(sharingGroupUUID:sharingGroupUUID, deferredUploadId: deferredUploadId)
        
        guard let uploadId1 = upload1.uploadId,
            let uploadId2 = upload2.uploadId else {
            XCTFail()
            return
        }
        
        guard let result = uploadRepo.select(forDeferredUploadIds: [deferredUploadId]),
            result.count == 2 else {
            XCTFail()
            return
        }
        
        let expectation = Set<Int64>([uploadId1, uploadId2])
        let actual = Set<Int64>(result.compactMap{$0.uploadId})

        XCTAssert(expectation == actual)
    }
    
    func testSelectForDeferredUploadIdsWithTwoUploadsAndTwoDeferredUploads() {
        let uploadRepo = UploadRepository(db)
        
        let sharingGroupUUID = UUID().uuidString
        guard case .success = SharingGroupRepository(db).add(sharingGroupUUID: sharingGroupUUID) else {
            XCTFail()
            return
        }
        
        guard let deferredUpload1 = doAddDeferredUpload(userId: 1, status: .pendingChange, sharingGroupUUID: sharingGroupUUID),
            let deferredUploadId1 = deferredUpload1.deferredUploadId else {
            XCTFail()
            return
        }
        
        guard let deferredUpload2 = doAddDeferredUpload(userId: 1, status: .pendingChange, sharingGroupUUID: sharingGroupUUID),
            let deferredUploadId2 = deferredUpload2.deferredUploadId else {
            XCTFail()
            return
        }
        
        let upload1 = doAddUpload(sharingGroupUUID:sharingGroupUUID, deferredUploadId: deferredUploadId1)
        let upload2 = doAddUpload(sharingGroupUUID:sharingGroupUUID, deferredUploadId: deferredUploadId2)
        
        guard let uploadId1 = upload1.uploadId,
            let uploadId2 = upload2.uploadId else {
            XCTFail()
            return
        }
        
        guard let result = uploadRepo.select(forDeferredUploadIds: [deferredUploadId1, deferredUploadId2]),
            result.count == 2 else {
            XCTFail()
            return
        }
        
        let expectation = Set<Int64>([uploadId1, uploadId2])
        let actual = Set<Int64>(result.compactMap{$0.uploadId})

        XCTAssert(expectation == actual)
    }
    
    func testLookupAll() {
        let sharingGroupUUID = UUID().uuidString
        guard case .success = SharingGroupRepository(db).add(sharingGroupUUID: sharingGroupUUID) else {
            XCTFail()
            return
        }
        
        let upload = doAddUpload(sharingGroupUUID:sharingGroupUUID, fileVersion: 1)
        
        let key =  UploadRepository.LookupKey.fileUUIDWithState(fileUUID: upload.fileUUID, state: .vNUploadFileChange)
        guard let vNFileFileChangeUploads = UploadRepository(db).lookupAll(key: key, modelInit: Upload.init) else {
            return
        }
        
        XCTAssert(vNFileFileChangeUploads.count == 1)
    }
}
