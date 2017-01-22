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
        _ = UserRepository.remove()
        _ = UserRepository.create()
        _ = UploadRepository.remove()
        _ = UploadRepository.create()
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
        
        let result1 = UserRepository.add(user: user1)
        XCTAssert(result1 == 1, "Bad credentialsId!")

        let user2 = User()
        user2.username = "Natasha"
        user2.accountType = .Google
        user2.creds = "{\"accessToken\": \"SomeAccessTokenValue2\"}"
        user2.credsId = "200"
        
        let result2 = UserRepository.add(user: user2)
        XCTAssert(result2 == 2, "Bad credentialsId!")
    }
    
    func testLookup1() {
        testAddUser()
        
        let result = UserRepository.lookup(key: .userId(1))
        switch result {
        case .error(let error):
            XCTFail("\(error)")
            
        case .found(let user):
            XCTAssert(user.accountType == .Google)
            XCTAssert(user.username == "Chris")
            XCTAssert(user.creds == "{\"accessToken\": \"SomeAccessTokenValue1\"}")
            XCTAssert(user.userId == 1)
            
        case .noUserFound:
            XCTFail("No User Found")
        }
    }
    
    func testLookup2() {
        testAddUser()
        
        let result = UserRepository.lookup(key: .accountTypeInfo(accountType:.Google, credsId:"100"))
        switch result {
        case .error(let error):
            XCTFail("\(error)")
            
        case .found(let user):
            XCTAssert(user.accountType == .Google)
            XCTAssert(user.username == "Chris")
            XCTAssert(user.creds == "{\"accessToken\": \"SomeAccessTokenValue1\"}")
            XCTAssert(user.userId == 1)
            guard let credsObject = user.credsObject as? GoogleCreds else {
                XCTFail()
                return
            }
            
            XCTAssert(credsObject.accessToken == "SomeAccessTokenValue1")
            
        case .noUserFound:
            XCTFail("No User Found")
        }
    }
    
    func doUpload() -> Upload {
        let upload = Upload()
        upload.deviceUUID = PerfectLib.UUID().string
        upload.fileSizeBytes = 100
        upload.fileUpload = true
        upload.fileUUID = PerfectLib.UUID().string
        upload.fileVersion = 1
        upload.mimeType = "text/plain"
        upload.state = .uploading
        upload.userId = 1
        upload.appMetaData = "{ \"foo\": \"bar\" }"
        
        let result1 = UploadRepository.add(upload: upload)
        XCTAssert(result1 == 1, "Bad uploadId!")
        
        return upload
    }
    
    func testAddUpload() {
        _ = doUpload()
    }
    
    func testLookupFromUpload() {
        let upload1 = doUpload()
        
        let result = UploadRepository.lookup(key: .uploadId(1))
        switch result {
        case .error(let error):
            XCTFail("\(error)")
            
        case .found(let upload2):
            XCTAssert(upload1.deviceUUID != nil && upload1.deviceUUID == upload2.deviceUUID)
            XCTAssert(upload1.fileSizeBytes != nil && upload1.fileSizeBytes == upload2.fileSizeBytes)
            XCTAssert(upload1.fileUpload != nil && upload1.fileUpload == upload2.fileUpload)
            XCTAssert(upload1.fileUUID != nil && upload1.fileUUID == upload2.fileUUID)
            XCTAssert(upload1.fileVersion != nil && upload1.fileVersion == upload2.fileVersion)
            XCTAssert(upload1.mimeType != nil && upload1.mimeType == upload2.mimeType)
            XCTAssert(upload1.state != nil && upload1.state == upload2.state)
            XCTAssert(upload1.userId != nil && upload1.userId == upload2.userId)
            XCTAssert(upload1.appMetaData != nil && upload1.appMetaData == upload2.appMetaData)

        case .noUploadFound:
            XCTFail("No Upload Found")
        }
    }
}
