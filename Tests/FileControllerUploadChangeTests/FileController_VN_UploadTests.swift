//
//  FileController_VN_UploadTests.swift
//  Server
//
//  Created by Christopher Prince on 7/26/17.
//
//

import XCTest
@testable import Server
@testable import TestsCommon
import LoggerAPI
import HeliumLogger
import Foundation
import ServerShared
import ChangeResolvers
import Credentials

class FileController_VN_UploadTests: ServerTestCase, UploaderCommon {
    var accountManager: AccountManager!
    
    override func setUp() {
        super.setUp()
        HeliumLogger.use(.debug)
        
        accountManager = AccountManager(userRepository: UserRepository(db))
        let credentials = Credentials()
        accountManager.setupAccounts(credentials: credentials)
    }
    
    func runUploadOneV1TextFileWorks(withFileGroup: Bool) {
        let changeResolverName = CommentFile.changeResolverName
        let deviceUUID = Foundation.UUID().uuidString
        let fileUUID = Foundation.UUID().uuidString
        
        var fileGroupUUID: String?
        if withFileGroup {
            fileGroupUUID = Foundation.UUID().uuidString
        }
        
        let exampleComment = ExampleComment(messageString: "Hello, World", id: Foundation.UUID().uuidString)
         
        // First upload the v0 file.
  
        guard let result = uploadTextFile(uploadIndex: 1, uploadCount: 1, deviceUUID:deviceUUID, fileUUID: fileUUID, stringFile: .commentFile, fileGroupUUID: fileGroupUUID, changeResolverName: changeResolverName),
            let sharingGroupUUID = result.sharingGroupUUID else {
            XCTFail()
            return
        }
        
        // Next, upload v1 of the file -- i.e., upload just the specific change to the file.
        
        let fileIndex = FileIndexRepository(db)
        let upload = UploadRepository(db)
        let deferredUploads = DeferredUploadRepository(db)
        
        guard let fileIndexCount1 = fileIndex.count(),
            let uploadCount1 = upload.count(),
            let deferredUploadCount1 = deferredUploads.count() else {
            XCTFail()
            return
        }
                
        let v1ChangeData = exampleComment.updateContents
        
        guard let _ = uploadTextFile(uploadIndex: 1, uploadCount: 1, testAccount: .primaryOwningAccount, deviceUUID: deviceUUID, fileUUID: fileUUID, addUser: .no(sharingGroupUUID: sharingGroupUUID), dataToUpload: v1ChangeData) else {
            XCTFail()
            return
        }
        
        XCTAssert(fileIndexCount1 == fileIndex.count() )
        XCTAssert(uploadCount1 == upload.count())
        XCTAssert(deferredUploadCount1 == deferredUploads.count())
    }
    
    func testUploadOneV1TextFileWorks() {
        runUploadOneV1TextFileWorks(withFileGroup: true)
    }
    
    func testUploadOneV1TextFileWithNoFileGroupWorks() {
        runUploadOneV1TextFileWorks(withFileGroup: false)
    }
    
    func runUploadTwoV1TextFilesInSameSharingGroupWorks(withFileGroup: Bool) {
        let changeResolverName = CommentFile.changeResolverName
        let deviceUUID = Foundation.UUID().uuidString
        let fileUUID1 = Foundation.UUID().uuidString
        let fileUUID2 = Foundation.UUID().uuidString

        var fileGroupUUID: String?
        if withFileGroup {
            fileGroupUUID = Foundation.UUID().uuidString
        }
        
        let exampleComment1 = ExampleComment(messageString: "Hello, World", id: Foundation.UUID().uuidString)
        let exampleComment2 = ExampleComment(messageString: "Goodbye!", id: Foundation.UUID().uuidString)

        // First upload the v0 files.
  
        guard let result = uploadTextFile(uploadIndex: 1, uploadCount: 2, deviceUUID:deviceUUID, fileUUID: fileUUID1, stringFile: .commentFile, fileGroupUUID: fileGroupUUID, changeResolverName: changeResolverName),
            let sharingGroupUUID = result.sharingGroupUUID else {
            XCTFail()
            return
        }
        
        guard let _ = uploadTextFile(uploadIndex: 2, uploadCount: 2, deviceUUID:deviceUUID, fileUUID: fileUUID2, addUser: .no(sharingGroupUUID: sharingGroupUUID), stringFile: .commentFile, fileGroupUUID: fileGroupUUID, changeResolverName: changeResolverName) else {
            XCTFail()
            return
        }
        
        // Next, upload v1 of the files -- i.e., upload just the specific changes to the files.
        
        let fileIndex = FileIndexRepository(db)
        let upload = UploadRepository(db)
        let deferredUploads = DeferredUploadRepository(db)
        
        guard let fileIndexCount1 = fileIndex.count(),
            let uploadCount1 = upload.count(),
            let deferredUploadCount1 = deferredUploads.count() else {
            XCTFail()
            return
        }
                
        let v1ChangeData1 = exampleComment1.updateContents
        let v1ChangeData2 = exampleComment2.updateContents
        
        Log.debug("Starting vN uploads...")

        guard let _ = uploadTextFile(uploadIndex: 1, uploadCount: 2, testAccount: .primaryOwningAccount, deviceUUID: deviceUUID, fileUUID: fileUUID1, addUser: .no(sharingGroupUUID: sharingGroupUUID), dataToUpload: v1ChangeData1) else {
            XCTFail()
            return
        }
        
        guard let _ = uploadTextFile(uploadIndex: 2, uploadCount: 2, testAccount: .primaryOwningAccount, deviceUUID: deviceUUID, fileUUID: fileUUID2, addUser: .no(sharingGroupUUID: sharingGroupUUID), dataToUpload: v1ChangeData2) else {
            XCTFail()
            return
        }
        
        XCTAssert(fileIndexCount1 == fileIndex.count() )
        XCTAssert(uploadCount1 == upload.count())
        XCTAssert(deferredUploadCount1 == deferredUploads.count())
    }
    
    func testUploadTwoV1TextFilesInSameSharingGroupWorks() {
        runUploadTwoV1TextFilesInSameSharingGroupWorks(withFileGroup: true)
    }
    
    func runUploadTwoV1Changes(fromDifferentFileGroupsInSameBatch: Bool) {
        let changeResolverName = CommentFile.changeResolverName
        let deviceUUID = Foundation.UUID().uuidString
        let fileUUID1 = Foundation.UUID().uuidString
        let fileUUID2 = Foundation.UUID().uuidString

        let fileGroupUUID1 = Foundation.UUID().uuidString
        let fileGroupUUID2: String

        if fromDifferentFileGroupsInSameBatch {
            fileGroupUUID2 = Foundation.UUID().uuidString
        }
        else {
            fileGroupUUID2 = fileGroupUUID1
        }
        
        let exampleComment1 = ExampleComment(messageString: "Hello, World", id: Foundation.UUID().uuidString)
        let exampleComment2 = ExampleComment(messageString: "Goodbye!", id: Foundation.UUID().uuidString)

        // First upload the v0 files. Will use separate batches here. What I want to test is the VN upload process.
  
        guard let result = uploadTextFile(uploadIndex: 1, uploadCount: 1, deviceUUID:deviceUUID, fileUUID: fileUUID1, stringFile: .commentFile, fileGroupUUID: fileGroupUUID1, changeResolverName: changeResolverName),
            let sharingGroupUUID = result.sharingGroupUUID else {
            XCTFail()
            return
        }
        
        let _ = uploadTextFile(uploadIndex: 1, uploadCount: 1, deviceUUID:deviceUUID, fileUUID: fileUUID2, addUser: .no(sharingGroupUUID: sharingGroupUUID), stringFile: .commentFile, fileGroupUUID: fileGroupUUID2, changeResolverName: changeResolverName)
        
        // Next, upload v1 of the files -- i.e., upload just the specific changes to the files.
        
        let fileIndex = FileIndexRepository(db)
        let upload = UploadRepository(db)
        let deferredUploads = DeferredUploadRepository(db)
        
        guard let fileIndexCount1 = fileIndex.count(),
            let uploadCount1 = upload.count(),
            let deferredUploadCount1 = deferredUploads.count() else {
            XCTFail()
            return
        }
                
        let v1ChangeData1 = exampleComment1.updateContents
        let v1ChangeData2 = exampleComment2.updateContents
        
        Log.debug("Starting vN uploads...")

        guard let _ = uploadTextFile(uploadIndex: 1, uploadCount: 2, testAccount: .primaryOwningAccount, deviceUUID: deviceUUID, fileUUID: fileUUID1, addUser: .no(sharingGroupUUID: sharingGroupUUID), dataToUpload: v1ChangeData1) else {
            XCTFail()
            return
        }
        
        // Expecting a failure here.
        let result2 = uploadTextFile(uploadIndex: 2, uploadCount: 2, testAccount: .primaryOwningAccount, deviceUUID: deviceUUID, fileUUID: fileUUID2, addUser: .no(sharingGroupUUID: sharingGroupUUID), errorExpected: fromDifferentFileGroupsInSameBatch, dataToUpload: v1ChangeData2)
        
        if !fromDifferentFileGroupsInSameBatch {
            XCTAssert(result2 != nil)
            XCTAssert(fileIndexCount1 == fileIndex.count() )
            XCTAssert(uploadCount1 == upload.count())
            XCTAssert(deferredUploadCount1 == deferredUploads.count())
        }
    }
    
    func testUploadTwoV1ChangesFromDifferentFileGroupsInSameBatchFails() {
        runUploadTwoV1Changes(fromDifferentFileGroupsInSameBatch: true)
    }
    
    func testUploadTwoV1ChangesFromSameFileGroupsInSameBatchWorks() {
        runUploadTwoV1Changes(fromDifferentFileGroupsInSameBatch: false)
    }
    
    // I'd like to run a test with multiple sharing groups, so that the Uploader async processing for the multiple groups takes place together.
    // Normally, in my test setup, this wouldn't happen. The Uploader run for the first batch would take place together, and the second batch would likely have to wait.
    // However, this situation, with the multiple sharing groups, is possible. It can happen if a Uploader run attempt after a batch upload can't get the lock because some other server instance has the lock.
    // I can do this test by faking the upload of the first batch: I can simulate another device/client uploading the first batch of files by uploading the file directly and making additions to FileIndex, Upload and DeferredUpload directly.
    // And then, the second batch can be done as usual-- with the regular file upload endpoint.
    func testUploadV1TextFilesInDifferentSharingGroupsWorks() {
        let changeResolverName = CommentFile.changeResolverName
        let deviceUUID = Foundation.UUID().uuidString
        let fileUUID1 = Foundation.UUID().uuidString
        let fileUUID2 = Foundation.UUID().uuidString

        let fileGroupUUID1 = Foundation.UUID().uuidString
        let fileGroupUUID2 = Foundation.UUID().uuidString
        
        let comment1 = ExampleComment(messageString: "Hello, World", id: Foundation.UUID().uuidString)
        let comment2 = ExampleComment(messageString: "Goodbye!", id: Foundation.UUID().uuidString)

        // First, do the v0 uploads.
  
        guard let result = uploadTextFile(uploadIndex: 1, uploadCount: 1, deviceUUID:deviceUUID, fileUUID: fileUUID1, stringFile: .commentFile, fileGroupUUID: fileGroupUUID1, changeResolverName: changeResolverName),
            let sharingGroupUUID1 = result.sharingGroupUUID else {
            XCTFail()
            return
        }
        
        let sharingGroup = ServerShared.SharingGroup()
        sharingGroup.sharingGroupName = "Louisiana Guys"
        let sharingGroupUUID2 = UUID().uuidString
        
        guard createSharingGroup(sharingGroupUUID: sharingGroupUUID2, deviceUUID:deviceUUID, sharingGroup: sharingGroup) else {
            XCTFail()
            return
        }
        
        guard let _ = uploadTextFile(uploadIndex: 1, uploadCount: 1, deviceUUID:deviceUUID, fileUUID: fileUUID2, addUser: .no(sharingGroupUUID: sharingGroupUUID2), stringFile: .commentFile, fileGroupUUID: fileGroupUUID2, changeResolverName: changeResolverName) else {
            XCTFail()
            return
        }
        
        let fileIndexRepo = FileIndexRepository(db)
        let uploadRepo = UploadRepository(db)
        let deferredUploadsRepo = DeferredUploadRepository(db)
        
        guard let fileIndexCount1 = fileIndexRepo.count(),
            let uploadCount1 = uploadRepo.count(),
            let deferredUploadCount1 = deferredUploadsRepo.count() else {
            XCTFail()
            return
        }

        // Next, prepare the vN uploads-- not using the upload file endpoint for the first one-- faking that another server instance uploaded it and it didn't have an Uploader run occurring.
        
       guard let fileIndex = getFileIndex(sharingGroupUUID: sharingGroupUUID1, fileUUID: fileUUID1) else {
            XCTFail()
            return
        }
        
        guard let deferredUpload1 = createDeferredUpload(userId: fileIndex.userId, fileGroupUUID: fileGroupUUID1, sharingGroupUUID: sharingGroupUUID1, status: .pendingChange),
            let deferredUploadId1 = deferredUpload1.deferredUploadId else {
            XCTFail()
            return
        }
        
        guard let _ = createUploadForTextFile(deviceUUID: deviceUUID, fileUUID: fileUUID1, sharingGroupUUID: sharingGroupUUID1, userId: fileIndex.userId, deferredUploadId: deferredUploadId1, updateContents: comment1.updateContents, uploadCount: 1, uploadIndex: 1) else {
            XCTFail()
            return
        }
        
        // Can do the second one normally. Both this upload and the faked one should get processed by Uploader run.
        
        guard let _ = uploadTextFile(uploadIndex: 1, uploadCount: 1, deviceUUID:deviceUUID, fileUUID: fileUUID2, addUser: .no(sharingGroupUUID: sharingGroupUUID2), dataToUpload: comment2.updateContents) else {
            XCTFail()
            return
        }
        
        guard let fileIndex1 = getFileIndex(sharingGroupUUID: sharingGroupUUID1, fileUUID: fileUUID1) else {
            XCTFail()
            return
        }
        
        XCTAssert(fileIndex1.fileVersion == 1)
        
        guard let fileIndex2 = getFileIndex(sharingGroupUUID: sharingGroupUUID2, fileUUID: fileUUID2) else {
            XCTFail()
            return
        }
        
        XCTAssert(fileIndex2.fileVersion == 1)
        
        XCTAssert(fileIndexCount1 == fileIndexRepo.count() )
        XCTAssert(uploadCount1 == uploadRepo.count())
        XCTAssert(deferredUploadCount1 == deferredUploadsRepo.count())
    }
}
