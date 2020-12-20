
import LoggerAPI
@testable import Server
@testable import TestsCommon
import KituraNet
import XCTest
import Foundation
import ServerShared
import ChangeResolvers
import Credentials
import ServerAccount

class ApplyDeferredUploadsTests: ServerTestCase, UploaderCommon {
    var accountManager:AccountManager!
    var resolverManager:ChangeResolverManager!
    var services:Services!
    
    override func setUp() {
        super.setUp()

        accountManager = AccountManager()
        let credentials = Credentials()
        accountManager.setupAccounts(credentials: credentials)
        resolverManager = ChangeResolverManager()

        guard let services = Services(accountManager: accountManager, changeResolverManager: resolverManager) else {
            XCTFail()
            return
        }
        
        self.services = services
        
        do {
            try resolverManager.setupResolvers()
        } catch let error {
            XCTFail("\(error)")
            return
        }
    }
    
    /*
    func testBoostrapInputFile() throws {
        let commentFile = CommentFile()
        let data = try commentFile.getData()
        
        guard let string = String(data: data, encoding: .utf8) else {
            XCTFail()
            return
        }
        
        Log.debug("string: \(string)")
    }
    */
    
    // MARK: ApplyDeferredUploads tests with a single file group
    
    func runApplyDeferredUploadsWithASingleFileAndOneChange(withFileGroup: Bool) throws {
        let deviceUUID = Foundation.UUID().uuidString
        let fileUUID = Foundation.UUID().uuidString
        
        var fileGroup: FileGroup?
        if withFileGroup {
            fileGroup = FileGroup(fileGroupUUID: Foundation.UUID().uuidString, objectType: "Foo")
        }

        let changeResolverName = CommentFile.changeResolverName

        // Do the v0 upload.
        guard let result = uploadTextFile(uploadIndex: 1, uploadCount: 1, deviceUUID:deviceUUID, fileUUID: fileUUID, fileLabel: UUID().uuidString, stringFile: .commentFile, fileGroup: fileGroup, changeResolverName: changeResolverName),
            let sharingGroupUUID = result.sharingGroupUUID else {
            XCTFail()
            return
        }
        
        let comment = ExampleComment(messageString: "Example", id: Foundation.UUID().uuidString)
        
        guard let fileIndex = getFileIndex(sharingGroupUUID: sharingGroupUUID, fileUUID: fileUUID) else {
            XCTFail()
            return
        }
        
        guard let deferredUpload = createDeferredUpload(userId: fileIndex.userId, fileGroupUUID: fileGroup?.fileGroupUUID, sharingGroupUUID: sharingGroupUUID, status: .pendingChange),
            let deferredUploadId = deferredUpload.deferredUploadId else {
            XCTFail()
            return
        }
        
        guard let _ = createUploadForTextFile(deviceUUID: deviceUUID, fileUUID: fileUUID, sharingGroupUUID: sharingGroupUUID, userId: fileIndex.userId, deferredUploadId: deferredUploadId, updateContents: comment.updateContents, uploadCount: 1, uploadIndex: 1) else {
            XCTFail()
            return
        }
        
        guard let applyDeferredUploads = try ApplyDeferredUploads(sharingGroupUUID: sharingGroupUUID, fileGroupUUID: fileGroup?.fileGroupUUID, deferredUploads: [deferredUpload], services: services.uploaderServices, db: db) else {
            XCTFail()
            return
        }
        
        let exp = expectation(description: "apply")
        
        applyDeferredUploads.run { error in
            XCTAssert(error == nil, "\(String(describing: error))")
            exp.fulfill()
        }
        
        waitExpectation(timeout: 10, handler: nil)
        
        guard checkCommentFile(expectedComment: comment, deviceUUID: deviceUUID, fileUUID: fileUUID, userId: fileIndex.userId) else {
            XCTFail()
            return
        }
    }
    
    func testApplyDeferredUploadsWithASingleFileAndOneChange() throws {
        try runApplyDeferredUploadsWithASingleFileAndOneChange(withFileGroup: true)
    }
    
    func testApplyDeferredUploadsWithNoFileGroupWithASingleFileAndOneChange() throws {
        try runApplyDeferredUploadsWithASingleFileAndOneChange(withFileGroup: false)
    }

    // I'm doing this using two DeferredUpload's -- to simulate the case where changes for the same file are uploaded in two separate batches. I.e., it probably doesn't make sense to think of multiple changes to the same file being uploaded in the same batch.
    func runApplyDeferredUploadsWithASingleFileAndTwoChanges(withFileGroup: Bool) throws {
        let deviceUUID = Foundation.UUID().uuidString
        let fileUUID = Foundation.UUID().uuidString
        
        var fileGroup: FileGroup?
        if withFileGroup {
            fileGroup = FileGroup(fileGroupUUID: Foundation.UUID().uuidString, objectType: "Foo")
        }

        let changeResolverName = CommentFile.changeResolverName

        // Do the v0 upload.
        guard let result = uploadTextFile(uploadIndex: 1, uploadCount: 1, deviceUUID:deviceUUID, fileUUID: fileUUID, fileLabel: UUID().uuidString, stringFile: .commentFile, fileGroup: fileGroup, changeResolverName: changeResolverName),
            let sharingGroupUUID = result.sharingGroupUUID else {
            XCTFail()
            return
        }
        
        let comment1 = ExampleComment(messageString: "Example", id: Foundation.UUID().uuidString)
        let comment2 = ExampleComment(messageString: "Another message", id: Foundation.UUID().uuidString)
        
        guard let fileIndex = getFileIndex(sharingGroupUUID: sharingGroupUUID, fileUUID: fileUUID) else {
            XCTFail()
            return
        }
        
        guard let deferredUpload1 = createDeferredUpload(userId: fileIndex.userId, fileGroupUUID: fileGroup?.fileGroupUUID, sharingGroupUUID: sharingGroupUUID, status: .pendingChange),
            let deferredUploadId1 = deferredUpload1.deferredUploadId else {
            XCTFail()
            return
        }
        
        guard let deferredUpload2 = createDeferredUpload(userId: fileIndex.userId, fileGroupUUID: fileGroup?.fileGroupUUID, sharingGroupUUID: sharingGroupUUID, status: .pendingChange),
            let deferredUploadId2 = deferredUpload2.deferredUploadId else {
            XCTFail()
            return
        }
        
        guard let _ = createUploadForTextFile(deviceUUID: deviceUUID, fileUUID: fileUUID, sharingGroupUUID: sharingGroupUUID, userId: fileIndex.userId, deferredUploadId: deferredUploadId1, updateContents: comment1.updateContents, uploadCount: 1, uploadIndex: 1) else {
            XCTFail()
            return
        }
        
        guard let _ = createUploadForTextFile(deviceUUID: deviceUUID, fileUUID: fileUUID, sharingGroupUUID: sharingGroupUUID, userId: fileIndex.userId, deferredUploadId: deferredUploadId2, updateContents: comment2.updateContents, uploadCount: 1, uploadIndex: 1) else {
            XCTFail()
            return
        }
        
        guard let applyDeferredUploads = try ApplyDeferredUploads(sharingGroupUUID: sharingGroupUUID, fileGroupUUID: fileGroup?.fileGroupUUID, deferredUploads: [deferredUpload1, deferredUpload2], services: services.uploaderServices, db: db) else {
            XCTFail()
            return
        }
        
        let exp = expectation(description: "apply")
        
        applyDeferredUploads.run { error in
            XCTAssert(error == nil, "\(String(describing: error))")
            exp.fulfill()
        }
        
        waitExpectation(timeout: 10, handler: nil)
        
        // Need to download v1 of the file, read it and check it's contents.

        guard checkCommentFile(expectedComment: comment1, recordIndex: 0, recordCount: 2, deviceUUID: deviceUUID, fileUUID: fileUUID, userId: fileIndex.userId) else {
            XCTFail()
            return
        }

         guard checkCommentFile(expectedComment: comment2, recordIndex: 1, recordCount: 2, deviceUUID: deviceUUID, fileUUID: fileUUID, userId: fileIndex.userId) else {
            XCTFail()
            return
        }
    }
    
    func testApplyDeferredUploadsWithASingleFileAndTwoChanges() throws {
        try runApplyDeferredUploadsWithASingleFileAndTwoChanges(withFileGroup: true)
    }
    
    func testApplyDeferredUploadsWithNoFileGroupWithASingleFileAndTwoChanges() throws {
        try runApplyDeferredUploadsWithASingleFileAndTwoChanges(withFileGroup: false)
    }
    
    func runApplyDeferredUploadsWithTwoFilesAndOneChangeEach(withFileGroup: Bool) throws {
        let deviceUUID = Foundation.UUID().uuidString
        let fileUUID1 = Foundation.UUID().uuidString
        let fileUUID2 = Foundation.UUID().uuidString
        
        var fileGroup: FileGroup?
        if withFileGroup {
            fileGroup = FileGroup(fileGroupUUID: Foundation.UUID().uuidString, objectType: "Foo")
        }

        let changeResolverName = CommentFile.changeResolverName

        // Do the v0 uploads.
        guard let result1 = uploadTextFile(uploadIndex: 1, uploadCount: 1, deviceUUID:deviceUUID, fileUUID: fileUUID1, fileLabel: UUID().uuidString, stringFile: .commentFile, fileGroup: fileGroup, changeResolverName: changeResolverName),
            let sharingGroupUUID = result1.sharingGroupUUID else {
            XCTFail()
            return
        }
        
        guard let _ = uploadTextFile(uploadIndex: 1, uploadCount: 1, deviceUUID:deviceUUID, fileUUID: fileUUID2, addUser: .no(sharingGroupUUID: sharingGroupUUID), fileLabel: UUID().uuidString, stringFile: .commentFile, fileGroup: fileGroup, changeResolverName: changeResolverName) else {
            XCTFail()
            return
        }
        
        let comment1 = ExampleComment(messageString: "Example", id: Foundation.UUID().uuidString)
        let comment2 = ExampleComment(messageString: "Another message", id: Foundation.UUID().uuidString)
        
        guard let fileIndex = getFileIndex(sharingGroupUUID: sharingGroupUUID, fileUUID: fileUUID1) else {
            XCTFail()
            return
        }
        
        guard let deferredUpload1 = createDeferredUpload(userId: fileIndex.userId, fileGroupUUID: fileGroup?.fileGroupUUID, sharingGroupUUID: sharingGroupUUID, status: .pendingChange),
            let deferredUploadId1 = deferredUpload1.deferredUploadId else {
            XCTFail()
            return
        }
        
        guard let deferredUpload2 = createDeferredUpload(userId: fileIndex.userId, fileGroupUUID: fileGroup?.fileGroupUUID, sharingGroupUUID: sharingGroupUUID, status: .pendingChange),
            let deferredUploadId2 = deferredUpload2.deferredUploadId else {
            XCTFail()
            return
        }
        
        guard let _ = createUploadForTextFile(deviceUUID: deviceUUID, fileUUID: fileUUID1, sharingGroupUUID: sharingGroupUUID, userId: fileIndex.userId, deferredUploadId: deferredUploadId1, updateContents: comment1.updateContents, uploadCount: 1, uploadIndex: 1) else {
            XCTFail()
            return
        }
        
        guard let _ = createUploadForTextFile(deviceUUID: deviceUUID, fileUUID: fileUUID2, sharingGroupUUID: sharingGroupUUID, userId: fileIndex.userId, deferredUploadId: deferredUploadId2, updateContents: comment2.updateContents, uploadCount: 1, uploadIndex: 1) else {
            XCTFail()
            return
        }
        
        guard let applyDeferredUploads = try ApplyDeferredUploads(sharingGroupUUID: sharingGroupUUID, fileGroupUUID: fileGroup?.fileGroupUUID, deferredUploads: [deferredUpload1, deferredUpload2], services: services.uploaderServices, db: db) else {
            XCTFail()
            return
        }
        
        let exp = expectation(description: "apply")
        
        applyDeferredUploads.run { error in
            XCTAssert(error == nil, "\(String(describing: error))")
            exp.fulfill()
        }
        
        waitExpectation(timeout: 10, handler: nil)
        
        guard checkCommentFile(expectedComment: comment1, deviceUUID: deviceUUID, fileUUID: fileUUID1, userId: fileIndex.userId) else {
            XCTFail()
            return
        }

         guard checkCommentFile(expectedComment: comment2, deviceUUID: deviceUUID, fileUUID: fileUUID2, userId: fileIndex.userId) else {
            XCTFail()
            return
        }
    }
    
    func testApplyDeferredUploadsWithTwoFilesAndOneChangeEach() throws {
        try runApplyDeferredUploadsWithTwoFilesAndOneChangeEach(withFileGroup: true)
    }
    
    func testApplyDeferredUploadsWithNoFileGroupWithTwoFilesAndOneChangeEach() throws {
        try runApplyDeferredUploadsWithTwoFilesAndOneChangeEach(withFileGroup: false)
    }
    
    // MARK: ApplyDeferredUploads tests with two file groups

    func runApplyDeferredUploadsWithTwoFileGroupsAndTwoFiles(withFileGroups: Bool) throws {
        let deviceUUID = Foundation.UUID().uuidString
        let fileUUID1 = Foundation.UUID().uuidString
        let fileUUID2 = Foundation.UUID().uuidString
        
        var fileGroup1: FileGroup?
        var fileGroup2: FileGroup?
        
        if withFileGroups {
            fileGroup1 = FileGroup(fileGroupUUID: Foundation.UUID().uuidString, objectType: "Foo")
            fileGroup2 = FileGroup(fileGroupUUID: Foundation.UUID().uuidString, objectType: "Foo")
        }
        
        let changeResolverName = CommentFile.changeResolverName

        // Do the v0 uploads.
        guard let result1 = uploadTextFile(uploadIndex: 1, uploadCount: 1, deviceUUID:deviceUUID, fileUUID: fileUUID1, fileLabel: UUID().uuidString, stringFile: .commentFile, fileGroup: fileGroup1, changeResolverName: changeResolverName),
            let sharingGroupUUID = result1.sharingGroupUUID else {
            XCTFail()
            return
        }
        
        guard let _ = uploadTextFile(uploadIndex: 1, uploadCount: 1, deviceUUID:deviceUUID, fileUUID: fileUUID2, addUser: .no(sharingGroupUUID: sharingGroupUUID), fileLabel: UUID().uuidString, stringFile: .commentFile, fileGroup: fileGroup2, changeResolverName: changeResolverName) else {
            XCTFail()
            return
        }
        
        let comment1 = ExampleComment(messageString: "Example", id: Foundation.UUID().uuidString)
        let comment2 = ExampleComment(messageString: "Another message", id: Foundation.UUID().uuidString)
        
        guard let fileIndex = getFileIndex(sharingGroupUUID: sharingGroupUUID, fileUUID: fileUUID1) else {
            XCTFail()
            return
        }

        guard let deferredUpload1 = createDeferredUpload(userId: fileIndex.userId, fileGroupUUID: fileGroup1?.fileGroupUUID, sharingGroupUUID: sharingGroupUUID, status: .pendingChange),
            let deferredUploadId1 = deferredUpload1.deferredUploadId else {
            XCTFail()
            return
        }
        
        guard let deferredUpload2 = createDeferredUpload(userId: fileIndex.userId, fileGroupUUID: fileGroup2?.fileGroupUUID, sharingGroupUUID: sharingGroupUUID, status: .pendingChange),
            let deferredUploadId2 = deferredUpload2.deferredUploadId else {
            XCTFail()
            return
        }
        
        guard let _ = createUploadForTextFile(deviceUUID: deviceUUID, fileUUID: fileUUID1, sharingGroupUUID: sharingGroupUUID, userId: fileIndex.userId, deferredUploadId: deferredUploadId1, updateContents: comment1.updateContents, uploadCount: 1, uploadIndex: 1) else {
            XCTFail()
            return
        }
        
        guard let _ = createUploadForTextFile(deviceUUID: deviceUUID, fileUUID: fileUUID2, sharingGroupUUID: sharingGroupUUID, userId: fileIndex.userId, deferredUploadId: deferredUploadId2, updateContents: comment2.updateContents, uploadCount: 1, uploadIndex: 1) else {
            XCTFail()
            return
        }
        
        guard let applyDeferredUploads1 = try ApplyDeferredUploads(sharingGroupUUID: sharingGroupUUID, fileGroupUUID: fileGroup1?.fileGroupUUID, deferredUploads: [deferredUpload1], services: services.uploaderServices,  db: db) else {
            XCTFail()
            return
        }
        
        // Apply deferred uploads for first file group
        
        let exp1 = expectation(description: "apply1")
        
        applyDeferredUploads1.run { error in
            XCTAssert(error == nil, "\(String(describing: error))")
            exp1.fulfill()
        }
        
        waitExpectation(timeout: 10, handler: nil)
        
        guard let applyDeferredUploads2 = try ApplyDeferredUploads(sharingGroupUUID: sharingGroupUUID, fileGroupUUID: fileGroup2?.fileGroupUUID, deferredUploads: [deferredUpload2], services: services.uploaderServices, db: db) else {
            XCTFail()
            return
        }
        
        // Apply deferred uploads for second file group

        let exp2 = expectation(description: "apply2")
        
        applyDeferredUploads2.run { error in
            XCTAssert(error == nil, "\(String(describing: error))")
            exp2.fulfill()
        }
        
        waitExpectation(timeout: 10, handler: nil)
        
        guard checkCommentFile(expectedComment: comment1, deviceUUID: deviceUUID, fileUUID: fileUUID1, userId: fileIndex.userId) else {
            XCTFail()
            return
        }

         guard checkCommentFile(expectedComment: comment2, deviceUUID: deviceUUID, fileUUID: fileUUID2, userId: fileIndex.userId) else {
            XCTFail()
            return
        }
    }
    
    func testApplyDeferredUploadsWithTwoFileGroupsAndTwoFiles() throws {
        try runApplyDeferredUploadsWithTwoFileGroupsAndTwoFiles(withFileGroups: true)
    }
    
    func testApplyDeferredWithNoFileGroupUploadsWithTwoFileGroupsAndTwoFiles() throws {
        try runApplyDeferredUploadsWithTwoFileGroupsAndTwoFiles(withFileGroups: false)
    }
}
