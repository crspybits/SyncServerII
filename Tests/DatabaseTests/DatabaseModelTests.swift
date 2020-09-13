//
//  DatabaseModelTests.swift
//  Server
//
//  Created by Christopher Prince on 5/2/17.
//
//

import XCTest
@testable import Server
@testable import TestsCommon
import LoggerAPI
import HeliumLogger
import Foundation
import ServerShared

class DatabaseModelTests: ServerTestCase {
    override func setUp() {
        super.setUp()
        HeliumLogger.use(.debug)
    }
    
    override func tearDown() {
        super.tearDown()
    }

    func testDeviceUUID() {
        let deviceUUID = DeviceUUID(userId: 0, deviceUUID: Foundation.UUID().uuidString)
        let newDeviceUUID = Foundation.UUID().uuidString
        let newUserId = Int64(10)
        
        deviceUUID[DeviceUUID.deviceUUIDKey] = newDeviceUUID
        deviceUUID[DeviceUUID.userIdKey] = newUserId
        
        XCTAssert(deviceUUID.deviceUUID == newDeviceUUID)
        XCTAssert(deviceUUID.userId == newUserId)

        deviceUUID[DeviceUUID.deviceUUIDKey] = nil
        deviceUUID[DeviceUUID.userIdKey] = nil
        
        XCTAssert(deviceUUID.deviceUUID == nil)
        XCTAssert(deviceUUID.userId == nil)
    }
    
    func testSharingInvitation() {
        let sharingInvitation = SharingInvitation()
        
        let newSharingInvitationUUID = Foundation.UUID().uuidString
        let newExpiry = Date()
        let newOwningUserId = UserId(342)
        let newSharingPermission:Permission = .read
        
        sharingInvitation[SharingInvitation.sharingInvitationUUIDKey] = newSharingInvitationUUID
        sharingInvitation[SharingInvitation.expiryKey] = newExpiry
        sharingInvitation[SharingInvitation.owningUserIdKey] = newOwningUserId
        sharingInvitation[SharingInvitation.permissionKey] = newSharingPermission
        
        XCTAssert(sharingInvitation.sharingInvitationUUID == newSharingInvitationUUID)
        XCTAssert(sharingInvitation.expiry == newExpiry)
        XCTAssert(sharingInvitation.owningUserId == newOwningUserId)
        XCTAssert(sharingInvitation.permission == newSharingPermission)

        sharingInvitation[SharingInvitation.sharingInvitationUUIDKey] = nil
        sharingInvitation[SharingInvitation.expiryKey] = nil
        sharingInvitation[SharingInvitation.owningUserIdKey] = nil
        sharingInvitation[SharingInvitation.permissionKey] = nil
        
        XCTAssert(sharingInvitation.sharingInvitationUUID == nil)
        XCTAssert(sharingInvitation.expiry == nil)
        XCTAssert(sharingInvitation.owningUserId == nil)
        XCTAssert(sharingInvitation.permission == nil)
    }
    
    func testUser() {
        let user = User()
        
        let newUserId = UserId(43287)
        let newUsername = "foobar"
        let newAccountType: AccountScheme.AccountName = AccountScheme.google.accountName
        let newCredsId = "d392y2t3"
        let newCreds = "fd9eu23y4"
        
        user[User.userIdKey] = newUserId
        user[User.usernameKey] = newUsername
        user[User.accountTypeKey] = newAccountType
        user[User.credsIdKey] = newCredsId
        user[User.credsKey] = newCreds
        
        XCTAssert(user.userId == newUserId)
        XCTAssert(user.username == newUsername)
        
        // Swift Compiler issues.
        // XCTAssert(user.accountType == newAccountType)
        
        if user.accountType != newAccountType {
            XCTFail()
        }
        
        XCTAssert(user.credsId == newCredsId)
        XCTAssert(user.creds == newCreds)
        
        user[User.userIdKey] = nil
        user[User.usernameKey] = nil
        user[User.accountTypeKey] = nil
        user[User.credsIdKey] = nil
        user[User.credsKey] = nil
        
        XCTAssert(user.userId == nil)
        XCTAssert(user.username == nil)
        XCTAssert(user.accountType == nil)
        XCTAssert(user.credsId == nil)
        XCTAssert(user.creds == nil)
    }
    
    func testFileIndex() {
        let fileIndex = FileIndex()

        let newFileIndexId = FileIndexId(334)
        let newFileUUID = Foundation.UUID().uuidString
        let newDeviceUUID = Foundation.UUID().uuidString
        let newUserId = UserId(3226453)
        let newMimeType = "text/plain"
        let newAppMetaData = "whatever"
        let newDeleted = false
        let newFileVersion = FileVersionInt(100)
        let newCheckSum = "abcdef"
        let creationDate = Date()
        let updateDate = Date()
        let changeResolverName = "SomeChangeResolver"
        let objectType = "SomeType"
        
        fileIndex[FileIndex.fileIndexIdKey] = newFileIndexId
        fileIndex[FileIndex.fileUUIDKey] = newFileUUID
        fileIndex[FileIndex.deviceUUIDKey] = newDeviceUUID
        fileIndex[FileIndex.userIdKey] = newUserId
        fileIndex[FileIndex.mimeTypeKey] = newMimeType
        fileIndex[FileIndex.appMetaDataKey] = newAppMetaData
        fileIndex[FileIndex.deletedKey] = newDeleted
        fileIndex[FileIndex.fileVersionKey] = newFileVersion
        fileIndex[FileIndex.lastUploadedCheckSumKey] = newCheckSum
        fileIndex[FileIndex.creationDateKey] = creationDate
        fileIndex[FileIndex.updateDateKey] = updateDate
        fileIndex[FileIndex.changeResolverNameKey] = changeResolverName
        fileIndex[FileIndex.objectTypeKey] = objectType
        
        XCTAssert(fileIndex.fileIndexId == newFileIndexId)
        XCTAssert(fileIndex.fileUUID == newFileUUID)
        XCTAssert(fileIndex.deviceUUID == newDeviceUUID)
        XCTAssert(fileIndex.userId == newUserId)
        XCTAssert(fileIndex.mimeType == newMimeType)
        XCTAssert(fileIndex.appMetaData == newAppMetaData)
        XCTAssert(fileIndex.deleted == newDeleted)
        XCTAssert(fileIndex.fileVersion == newFileVersion)
        XCTAssert(fileIndex.lastUploadedCheckSum == newCheckSum)
        XCTAssert(fileIndex.creationDate == creationDate)
        XCTAssert(fileIndex.updateDate == updateDate)
        XCTAssert(fileIndex.changeResolverName == changeResolverName)
        XCTAssert(fileIndex.objectType == objectType)

        fileIndex[FileIndex.fileIndexIdKey] = nil
        fileIndex[FileIndex.fileUUIDKey] = nil
        fileIndex[FileIndex.deviceUUIDKey] = nil
        fileIndex[FileIndex.userIdKey] = nil
        fileIndex[FileIndex.mimeTypeKey] = nil
        fileIndex[FileIndex.appMetaDataKey] = nil
        fileIndex[FileIndex.deletedKey] = nil
        fileIndex[FileIndex.fileVersionKey] = nil
        fileIndex[FileIndex.lastUploadedCheckSumKey] = nil
        fileIndex[FileIndex.creationDateKey] = nil
        fileIndex[FileIndex.updateDateKey] = nil
        fileIndex[FileIndex.changeResolverNameKey] = nil
        fileIndex[FileIndex.objectTypeKey] = nil

        XCTAssert(fileIndex.fileIndexId == nil)
        XCTAssert(fileIndex.fileUUID == nil)
        XCTAssert(fileIndex.deviceUUID == nil)
        XCTAssert(fileIndex.userId == nil)
        XCTAssert(fileIndex.mimeType == nil)
        XCTAssert(fileIndex.appMetaData == nil)
        XCTAssert(fileIndex.deleted == nil)
        XCTAssert(fileIndex.fileVersion == nil)
        XCTAssert(fileIndex.lastUploadedCheckSum == nil)
        XCTAssert(fileIndex.creationDate == nil)
        XCTAssert(fileIndex.updateDate == nil)
        XCTAssert(fileIndex.changeResolverName == nil)
        XCTAssert(fileIndex.objectType == nil)
    }
    
    func testUpload() {
        let upload = Upload()
        
        let uploadId = Int64(3300)
        let fileUUID = Foundation.UUID().uuidString
        let userId = UserId(43)
        let fileVersion = FileVersionInt(322)
        let deviceUUID = Foundation.UUID().uuidString
        let state:UploadState = .deleteSingleFile
        let appMetaData = "arba"
        let fileCheckSum = TestFile.test1.dropboxCheckSum
        let mimeType = "text/plain"
        let creationDate = Date()
        let updateDate = Date()
        let changeResolverName = "SomeChangeResolver"
        guard let contents = "Foobar bloobly".data(using: .utf8) else {
            XCTFail()
            return
        }
        let uploadCount:Int32 = 1
        let uploadIndex:Int32 = 2
        let objectType = "ObjectType"
        
        upload[Upload.uploadIdKey] = uploadId
        upload[Upload.fileUUIDKey] = fileUUID
        upload[Upload.userIdKey] = userId
        upload[Upload.fileVersionKey] = fileVersion
        upload[Upload.deviceUUIDKey] = deviceUUID
        upload[Upload.stateKey] = state
        upload[Upload.appMetaDataKey] = appMetaData
        upload[Upload.lastUploadedCheckSumKey] = fileCheckSum
        upload[Upload.mimeTypeKey] = mimeType
        upload[Upload.creationDateKey] = creationDate
        upload[Upload.updateDateKey] = updateDate
        upload[Upload.uploadContentsKey] = contents
        upload[Upload.uploadIndexKey] = uploadIndex
        upload[Upload.uploadCountKey] = uploadCount
        upload[Upload.changeResolverNameKey] = changeResolverName
        upload[Upload.objectTypeKey] = objectType
        
        XCTAssert(upload.uploadId == uploadId)
        XCTAssert(upload.fileUUID == fileUUID)
        XCTAssert(upload.userId == userId)
        XCTAssert(upload.fileVersion == fileVersion)
        XCTAssert(upload.deviceUUID == deviceUUID)
        XCTAssert(upload.state == state)
        XCTAssert(upload.appMetaData == appMetaData)
        XCTAssert(upload.lastUploadedCheckSum == fileCheckSum)
        XCTAssert(upload.mimeType == mimeType)
        XCTAssert(upload.creationDate == creationDate)
        XCTAssert(upload.updateDate == updateDate)
        XCTAssert(upload.uploadContents == contents)
        XCTAssert(upload.uploadIndex == uploadIndex)
        XCTAssert(upload.changeResolverName == changeResolverName)
        XCTAssert(upload.objectType == objectType)

        guard let count = upload.uploadCount else {
            XCTFail()
            return
        }
        XCTAssert(count == uploadCount)
        
        upload[Upload.uploadIdKey] = nil
        upload[Upload.fileUUIDKey] = nil
        upload[Upload.userIdKey] = nil
        upload[Upload.fileVersionKey] = nil
        upload[Upload.deviceUUIDKey] = nil
        upload[Upload.stateKey] = nil
        upload[Upload.appMetaDataKey] = nil
        upload[Upload.lastUploadedCheckSumKey] = nil
        upload[Upload.mimeTypeKey] = nil
        upload[Upload.creationDateKey] = nil
        upload[Upload.updateDateKey] = nil
        upload[Upload.uploadContentsKey] = nil
        upload[Upload.uploadIndexKey] = nil
        upload[Upload.uploadCountKey] = nil
        upload[Upload.changeResolverNameKey] = nil
        upload[Upload.objectTypeKey] = nil

        XCTAssert(upload.uploadId == nil)
        XCTAssert(upload.fileUUID == nil)
        XCTAssert(upload.userId == nil)
        XCTAssert(upload.fileVersion == nil)
        XCTAssert(upload.deviceUUID == nil)
        XCTAssert(upload.state == nil)
        XCTAssert(upload.appMetaData == nil)
        XCTAssert(upload.lastUploadedCheckSum == nil)
        XCTAssert(upload.mimeType == nil)
        XCTAssert(upload.creationDate == nil)
        XCTAssert(upload.updateDate == nil)
        XCTAssert(upload.uploadContents == nil)
        XCTAssert(upload.uploadIndex == nil)
        XCTAssert(upload.uploadCount == nil)
        XCTAssert(upload.changeResolverName == nil)
        XCTAssert(upload.objectType == nil)
    }
    
    // SharingGroup
    
    // SharingGroupUser
}

