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

    func doAddUpload(sharingGroupId: SharingGroupId, fileSizeBytes:Int64?=100, mimeType:String? = "text/plain", appMetaData:AppMetaData? = AppMetaData(version: 0, contents: "{ \"foo\": \"bar\" }"), userId:UserId = 1, deviceUUID:String = Foundation.UUID().uuidString, missingField:Bool = false) -> Upload {
        let upload = Upload()
        
        if !missingField {
            upload.deviceUUID = deviceUUID
        }
        
        upload.fileSizeBytes = fileSizeBytes
        upload.fileUUID = Foundation.UUID().uuidString
        upload.fileVersion = 1
        upload.mimeType = mimeType
        upload.state = .uploadingFile
        upload.userId = userId
        upload.appMetaData = appMetaData?.contents
        upload.appMetaDataVersion = appMetaData?.version
        upload.creationDate = Date()
        upload.updateDate = Date()
        upload.sharingGroupId = sharingGroupId
        
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
        
        if !missingField {
            XCTAssert(uploadId == 1, "Bad uploadId!")
        }
        
        upload.uploadId = uploadId
        
        return upload
    }
    
    func testAddUpload() {
        guard case .success(let sharingGroupId) = SharingGroupRepository(db).add() else {
            XCTFail()
            return
        }
        
        _ = doAddUpload(sharingGroupId:sharingGroupId)
    }
    
    func testAddUploadWithMissingField() {
        guard case .success(let sharingGroupId) = SharingGroupRepository(db).add() else {
            XCTFail()
            return
        }
        
        _ = doAddUpload(sharingGroupId:sharingGroupId, missingField: true)
    }
    
    func doAddUploadDeletion(sharingGroupId: SharingGroupId, userId:UserId = 1, deviceUUID:String = Foundation.UUID().uuidString, missingField:Bool = false) -> Upload {
        let upload = Upload()
        upload.deviceUUID = deviceUUID
        upload.fileUUID = Foundation.UUID().uuidString
        upload.fileVersion = 1
        upload.state = .toDeleteFromFileIndex
        upload.sharingGroupId = sharingGroupId

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
        guard case .success(let sharingGroupId) = SharingGroupRepository(db).add() else {
            XCTFail()
            return
        }
        
        _ = doAddUploadDeletion(sharingGroupId:sharingGroupId)
    }
    
    func testAddUploadDeletionWithMissingField() {
        guard case .success(let sharingGroupId) = SharingGroupRepository(db).add() else {
            XCTFail()
            return
        }
        
        _ = doAddUploadDeletion(sharingGroupId:sharingGroupId, missingField:true)
    }
    
    func testAddUploadSucceedsWithNilAppMetaData() {
        guard case .success(let sharingGroupId) = SharingGroupRepository(db).add() else {
            XCTFail()
            return
        }
        
        _ = doAddUpload(sharingGroupId:sharingGroupId, appMetaData:nil)
    }
    
    func testAddUploadSucceedsWithNilFileSizeBytes() {
        guard case .success(let sharingGroupId) = SharingGroupRepository(db).add() else {
            XCTFail()
            return
        }
        
        _ = doAddUpload(sharingGroupId:sharingGroupId, fileSizeBytes:nil)
    }
    
    func testUpdateUpload() {
        guard case .success(let sharingGroupId) = SharingGroupRepository(db).add() else {
            XCTFail()
            return
        }
        
        let upload = doAddUpload(sharingGroupId:sharingGroupId)
        XCTAssert(UploadRepository(db).update(upload: upload))
    }
    
    func testUpdateUploadFailsWithoutUploadId() {
        guard case .success(let sharingGroupId) = SharingGroupRepository(db).add() else {
            XCTFail()
            return
        }
        
        let upload = doAddUpload(sharingGroupId:sharingGroupId)
        upload.uploadId = nil
        XCTAssert(!UploadRepository(db).update(upload: upload))
    }
    
    func testUpdateUploadToUploadedFailsWithoutFileSizeBytes() {
        guard case .success(let sharingGroupId) = SharingGroupRepository(db).add() else {
            XCTFail()
            return
        }
        
        let upload = doAddUpload(sharingGroupId:sharingGroupId)
        upload.fileSizeBytes = nil
        upload.state = .uploadedFile
        XCTAssert(!UploadRepository(db).update(upload: upload))
    }
    
    func testUpdateUploadSucceedsWithNilAppMetaData() {
        guard case .success(let sharingGroupId) = SharingGroupRepository(db).add() else {
            XCTFail()
            return
        }
        
        let upload = doAddUpload(sharingGroupId:sharingGroupId)
        upload.appMetaData = nil
        upload.appMetaDataVersion = nil
        XCTAssert(UploadRepository(db).update(upload: upload))
    }
    
    func testLookupFromUpload() {
        guard case .success(let sharingGroupId) = SharingGroupRepository(db).add() else {
            XCTFail()
            return
        }
        
        let upload1 = doAddUpload(sharingGroupId:sharingGroupId)
        
        let result = UploadRepository(db).lookup(key: .uploadId(1), modelInit: Upload.init)
        switch result {
        case .error(let error):
            XCTFail("\(error)")
            
        case .found(let object):
            let upload2 = object as! Upload
            XCTAssert(upload1.deviceUUID != nil && upload1.deviceUUID == upload2.deviceUUID)
            XCTAssert(upload1.fileSizeBytes != nil && upload1.fileSizeBytes == upload2.fileSizeBytes)
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
        user1.permission = .admin
        
        let result1 = UserRepository(db).add(user: user1)
        XCTAssert(result1 == 1, "Bad credentialsId!")
        
        let uploadedFilesResult = UploadRepository(db).uploadedFiles(forUserId: result1!, deviceUUID: Foundation.UUID().uuidString)
        switch uploadedFilesResult {
        case .uploads(let uploads):
            XCTAssert(uploads.count == 0)
        case .error(_):
            XCTFail()
        }
    }

    func testUploadedIndexWithOneFile() {
        let user1 = User()
        user1.username = "Chris"
        user1.accountType = .Google
        user1.creds = "{\"accessToken\": \"SomeAccessTokenValue1\"}"
        user1.credsId = "100"
        user1.permission = .read
        
        let userId = UserRepository(db).add(user: user1)
        XCTAssert(userId == 1, "Bad credentialsId!")
        
        guard case .success(let sharingGroupId) = SharingGroupRepository(db).add() else {
            XCTFail()
            return
        }
        
        let deviceUUID = Foundation.UUID().uuidString
        let upload1 = doAddUpload(sharingGroupId:sharingGroupId, userId:userId!, deviceUUID:deviceUUID)

        let uploadedFilesResult = UploadRepository(db).uploadedFiles(forUserId: userId!, deviceUUID: deviceUUID)
        switch uploadedFilesResult {
        case .uploads(let uploads):
            XCTAssert(uploads.count == 1)
            XCTAssert(upload1.appMetaData == uploads[0].appMetaData)
            XCTAssert(upload1.fileUUID == uploads[0].fileUUID)
            XCTAssert(upload1.fileVersion == uploads[0].fileVersion)
            XCTAssert(upload1.mimeType == uploads[0].mimeType)
            XCTAssert(upload1.fileSizeBytes == uploads[0].fileSizeBytes)
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
            ("testAddUploadSucceedsWithNilFileSizeBytes", testAddUploadSucceedsWithNilFileSizeBytes),
            ("testUpdateUpload", testUpdateUpload),
            ("testUpdateUploadFailsWithoutUploadId", testUpdateUploadFailsWithoutUploadId),
            ("testUpdateUploadToUploadedFailsWithoutFileSizeBytes", testUpdateUploadToUploadedFailsWithoutFileSizeBytes),
            ("testUpdateUploadSucceedsWithNilAppMetaData", testUpdateUploadSucceedsWithNilAppMetaData),
            ("testLookupFromUpload", testLookupFromUpload),
            ("testGetUploadsWithNoFiles", testGetUploadsWithNoFiles),
            ("testUploadedIndexWithOneFile", testUploadedIndexWithOneFile)
        ]
    }
    
    func testLinuxTestSuiteIncludesAllTests() {
        linuxTestSuiteIncludesAllTests(testType: SpecificDatabaseTests_Uploads.self)
    }
}
