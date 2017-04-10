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
import PerfectLib
import Foundation

class SpecificDatabaseTests_Uploads: ServerTestCase {

    override func setUp() {
        super.setUp()
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }
    
    override func tearDown() {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
        super.tearDown()
    }

    func doAddUpload(fileSizeBytes:Int64?=100, mimeType:String? = "text/plain", appMetaData:String? = "{ \"foo\": \"bar\" }", userId:UserId = 1, deviceUUID:String = PerfectLib.UUID().string) -> Upload {
        let upload = Upload()
        upload.deviceUUID = deviceUUID
        upload.fileSizeBytes = fileSizeBytes
        upload.fileUUID = PerfectLib.UUID().string
        upload.fileVersion = 1
        upload.mimeType = mimeType
        upload.state = .uploaded
        upload.userId = userId
        upload.appMetaData = appMetaData
        
        let result = UploadRepository(db).add(upload: upload)
        
        var uploadId:Int64!
        switch result {
        case .success(uploadId: let id):
            uploadId = id
        
        default:
            XCTFail()
        }
        
        XCTAssert(uploadId == 1, "Bad uploadId!")
        
        upload.uploadId = uploadId
        
        return upload
    }
    
    func testAddUpload() {
        _ = doAddUpload()
    }
    
    func testAddUploadSucceedsWithNilFileSizeBytes() {
        _ = doAddUpload(fileSizeBytes:nil)
    }
    
    func testAddUploadSucceedsWithNilAppMetaData() {
        _ = doAddUpload(appMetaData:nil)
    }
    
    func testAddUploadSucceedsWithNilMimeType() {
        _ = doAddUpload(mimeType:nil)
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
    
    func testUpdateUploadSucceedsWithNilAppMetaData() {
        let upload = doAddUpload()
        upload.appMetaData = nil
        XCTAssert(UploadRepository(db).update(upload: upload))
    }
    
    func testUpdateUploadSucceedsWithNilMimeType() {
        let upload = doAddUpload()
        upload.mimeType = nil
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
        
        let uploadedFilesResult = UploadRepository(db).uploadedFiles(forUserId: result1!, deviceUUID: PerfectLib.UUID().string)
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
        
        let userId = UserRepository(db).add(user: user1)
        XCTAssert(userId == 1, "Bad credentialsId!")
        
        let deviceUUID = PerfectLib.UUID().string
        let upload1 = doAddUpload(userId:userId!, deviceUUID:deviceUUID)

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
