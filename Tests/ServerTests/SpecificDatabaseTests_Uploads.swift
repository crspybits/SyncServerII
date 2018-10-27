//
//  SpecificDatabaseTests_Uploads.swift
//  Server
//
//  Created by Christopher Prince on 2/18/17.
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

class SpecificDatabaseTests_Uploads: ServerTestCase, LinuxTestable {

    override func setUp() {
        super.setUp()
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }
    
    override func tearDown() {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
        super.tearDown()
    }

    func doAddUpload(sharingGroupUUID: String, checkSum: String? = "", mimeType:String? = "text/plain", appMetaData:AppMetaData? = AppMetaData(version: 0, contents: "{ \"foo\": \"bar\" }"), userId:UserId = 1, deviceUUID:String = Foundation.UUID().uuidString, missingField:Bool = false) -> Upload {
        let upload = Upload()
        
        if !missingField {
            upload.deviceUUID = deviceUUID
        }
        
        upload.lastUploadedCheckSum = checkSum
        upload.fileUUID = Foundation.UUID().uuidString
        upload.fileVersion = 1
        upload.mimeType = mimeType
        upload.state = .uploadingFile
        upload.userId = userId
        upload.appMetaData = appMetaData?.contents
        upload.appMetaDataVersion = appMetaData?.version
        upload.creationDate = Date()
        upload.updateDate = Date()
        upload.sharingGroupUUID = sharingGroupUUID
        
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
        
        upload.uploadId = uploadId
        
        return upload
    }
    
    func testAddUpload() {
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
        
        _ = doAddUpload(sharingGroupUUID:sharingGroupUUID, missingField: true)
    }
    
    func doAddUploadDeletion(sharingGroupUUID: String, userId:UserId = 1, deviceUUID:String = Foundation.UUID().uuidString, missingField:Bool = false) -> Upload {
        let upload = Upload()
        upload.deviceUUID = deviceUUID
        upload.fileUUID = Foundation.UUID().uuidString
        upload.fileVersion = 1
        upload.state = .toDeleteFromFileIndex
        upload.sharingGroupUUID = sharingGroupUUID

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
    
    func testAddUploadSucceedsWithNilCheckSum() {
        let sharingGroupUUID = UUID().uuidString
        guard case .success = SharingGroupRepository(db).add(sharingGroupUUID: sharingGroupUUID) else {
            XCTFail()
            return
        }
        
        _ = doAddUpload(sharingGroupUUID:sharingGroupUUID, checkSum:nil)
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
    
    func testUpdateUploadToUploadedFailsWithoutCheckSum() {
        let sharingGroupUUID = UUID().uuidString
        guard case .success = SharingGroupRepository(db).add(sharingGroupUUID: sharingGroupUUID) else {
            XCTFail()
            return
        }
        
        let upload = doAddUpload(sharingGroupUUID:sharingGroupUUID)
        upload.lastUploadedCheckSum = nil
        upload.state = .uploadedFile
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
        upload.appMetaDataVersion = nil
        XCTAssert(UploadRepository(db).update(upload: upload))
    }
    
    func testLookupFromUpload() {
        let sharingGroupUUID = UUID().uuidString
        guard case .success = SharingGroupRepository(db).add(sharingGroupUUID: sharingGroupUUID) else {
            XCTFail()
            return
        }
        
        let upload1 = doAddUpload(sharingGroupUUID:sharingGroupUUID)
        
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

        case .noObjectFound:
            XCTFail("No Upload Found")
        }
    }
    
    func testGetUploadsWithNoFiles() {
        let user1 = User()
        user1.username = "Chris"
        user1.accountType = .Google
        user1.creds = "{\"accessToken\": \"SomeAccessTokenValue1\"}"
        user1.credsId = "100"
        
        let result1 = UserRepository(db).add(user: user1)
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
        let sharingGroupUUID = UUID().uuidString
        let user1 = User()
        user1.username = "Chris"
        user1.accountType = .Google
        user1.creds = "{\"accessToken\": \"SomeAccessTokenValue1\"}"
        user1.credsId = "100"
        
        let userId = UserRepository(db).add(user: user1)
        XCTAssert(userId == 1, "Bad credentialsId!")
        
        guard case .success = SharingGroupRepository(db).add(sharingGroupUUID: sharingGroupUUID) else {
            XCTFail()
            return
        }
        
        let deviceUUID = Foundation.UUID().uuidString
        let upload1 = doAddUpload(sharingGroupUUID:sharingGroupUUID, userId:userId!, deviceUUID:deviceUUID)

        let uploadedFilesResult = UploadRepository(db).uploadedFiles(forUserId: userId!, sharingGroupUUID: sharingGroupUUID, deviceUUID: deviceUUID)
        switch uploadedFilesResult {
        case .uploads(let uploads):
            XCTAssert(uploads.count == 1)
            XCTAssert(upload1.appMetaData == uploads[0].appMetaData)
            XCTAssert(upload1.fileUUID == uploads[0].fileUUID)
            XCTAssert(upload1.fileVersion == uploads[0].fileVersion)
            XCTAssert(upload1.mimeType == uploads[0].mimeType)
            XCTAssert(upload1.lastUploadedCheckSum == uploads[0].lastUploadedCheckSum)
        case .error(_):
            XCTFail()
        }
    }
    
    func testUploadedIndexWithInterleavedSharingGroupFiles() {
        let sharingGroupUUID1 = UUID().uuidString
        let sharingGroupUUID2 = UUID().uuidString

        let user1 = User()
        user1.username = "Chris"
        user1.accountType = .Google
        user1.creds = "{\"accessToken\": \"SomeAccessTokenValue1\"}"
        user1.credsId = "100"
        
        let userId = UserRepository(db).add(user: user1)
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
}

extension SpecificDatabaseTests_Uploads {
    static var allTests : [(String, (SpecificDatabaseTests_Uploads) -> () throws -> Void)] {
        return [
            ("testAddUpload", testAddUpload),
            ("testAddUploadWithMissingField", testAddUploadWithMissingField),
            ("testAddUploadDeletion", testAddUploadDeletion),
            ("testAddUploadDeletionWithMissingField", testAddUploadDeletionWithMissingField),
            ("testAddUploadSucceedsWithNilAppMetaData", testAddUploadSucceedsWithNilAppMetaData),
            ("testAddUploadSucceedsWithNilCheckSum", testAddUploadSucceedsWithNilCheckSum),
            ("testUpdateUpload", testUpdateUpload),
            ("testUpdateUploadFailsWithoutUploadId", testUpdateUploadFailsWithoutUploadId),
            ("testUpdateUploadToUploadedFailsWithoutCheckSum", testUpdateUploadToUploadedFailsWithoutCheckSum),
            ("testUpdateUploadSucceedsWithNilAppMetaData", testUpdateUploadSucceedsWithNilAppMetaData),
            ("testLookupFromUpload", testLookupFromUpload),
            ("testGetUploadsWithNoFiles", testGetUploadsWithNoFiles),
            ("testUploadedIndexWithOneFile", testUploadedIndexWithOneFile),
            ("testUploadedIndexWithInterleavedSharingGroupFiles", testUploadedIndexWithInterleavedSharingGroupFiles)
        ]
    }
    
    func testLinuxTestSuiteIncludesAllTests() {
        linuxTestSuiteIncludesAllTests(testType: SpecificDatabaseTests_Uploads.self)
    }
}
