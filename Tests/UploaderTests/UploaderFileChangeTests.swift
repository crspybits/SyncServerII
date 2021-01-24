//
//  UploaderTests.swift
//  ChangeResolverTests
//
//  Created by Christopher G Prince on 7/21/20.
//

import LoggerAPI
@testable import Server
@testable import TestsCommon
import KituraNet
import XCTest
import Foundation
import ServerShared
import ChangeResolvers
import Credentials

class UploaderFileChangeTests: ServerTestCase, UploaderCommon {
    var accountManager: AccountManager!
    var uploader: Uploader!
    var runCompleted:((Swift.Error?)->())?
    
    override func setUp() {
        super.setUp()
        
        accountManager = AccountManager()
        accountManager.setupAccounts(credentials: Credentials())
        let resolverManager = ChangeResolverManager()
        
        guard let services = Services(accountManager: accountManager, changeResolverManager: resolverManager) else {
            XCTFail()
            return
        }
        
        do {
            try resolverManager.setupResolvers()
        } catch let error {
            XCTFail("\(error)")
            return
        }
        
        uploader = Uploader(services: services.uploaderServices, delegate: nil)

        uploader.delegate = self
        runCompleted = nil
    }
    
    override func tearDown() {
        super.tearDown()
        // Not sure why this is needed, but without this, the test accumulates un-closed db connections.
        uploader = nil
    }
    
    // MARK: One sharing group

    func runUploaderWithASingleFileWithOneChange(withFileGroup: Bool) throws {
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
        
        let exp = expectation(description: "run")
        
        runCompleted = { error in
            XCTAssert(error == nil)
            exp.fulfill()
        }
        
        try uploader.run()
        
        waitForExpectations(timeout: 10, handler: nil)
        
        guard checkCommentFile(expectedComment: comment, deviceUUID: deviceUUID, fileUUID: fileUUID, userId: fileIndex.userId) else {
            XCTFail()
            return
        }
    }
    
    func testUploaderWithASingleFileWithOneChange() throws {
        try runUploaderWithASingleFileWithOneChange(withFileGroup: true)
    }
    
    func testUploaderWithNoFileGroupWithASingleFileWithOneChange() throws {
        try runUploaderWithASingleFileWithOneChange(withFileGroup: false)
    }
    
    func runUploaderWithASingleFileAndTwoChanges(withFileGroup: Bool) throws {
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
        
        // Upload two changes to the same file.
        
        guard let _ = createUploadForTextFile(deviceUUID: deviceUUID, fileUUID: fileUUID, sharingGroupUUID: sharingGroupUUID, userId: fileIndex.userId, deferredUploadId: deferredUploadId1, updateContents: comment1.updateContents, uploadCount: 1, uploadIndex: 1) else {
            XCTFail()
            return
        }
        
        guard let _ = createUploadForTextFile(deviceUUID: deviceUUID, fileUUID: fileUUID, sharingGroupUUID: sharingGroupUUID, userId: fileIndex.userId, deferredUploadId: deferredUploadId2, updateContents: comment2.updateContents, uploadCount: 1, uploadIndex: 1) else {
            XCTFail()
            return
        }
        
        let exp = expectation(description: "run")
        
        runCompleted = { error in
            XCTAssert(error == nil)
            exp.fulfill()
        }
        
        try uploader.run()
        
        waitForExpectations(timeout: 10, handler: nil)
        
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
    
    func testUploaderWithASingleFileAndTwoChanges() throws {
        try runUploaderWithASingleFileAndTwoChanges(withFileGroup: true)
    }
    
    func testUploaderWithNoFileGroupWithASingleFileAndTwoChanges() throws {
        try runUploaderWithASingleFileAndTwoChanges(withFileGroup: false)
    }

    func runUploaderWithTwoFilesAndOneChangeEach(withFileGroup:Bool) throws {
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
        
        let exp = expectation(description: "run")
        
        runCompleted = { error in
            XCTAssert(error == nil)
            exp.fulfill()
        }
        
        try uploader.run()
        
        waitForExpectations(timeout: 20, handler: nil)
        
        guard checkCommentFile(expectedComment: comment1, deviceUUID: deviceUUID, fileUUID: fileUUID1, userId: fileIndex.userId) else {
            XCTFail()
            return
        }

         guard checkCommentFile(expectedComment: comment2, deviceUUID: deviceUUID, fileUUID: fileUUID2, userId: fileIndex.userId) else {
            XCTFail()
            return
        }
    }
    
    func testUploaderWithTwoFilesAndOneChangeEach() throws {
        try runUploaderWithTwoFilesAndOneChangeEach(withFileGroup: true)
    }
    
    func testUploaderWithNoFileGroupWithTwoFilesAndOneChangeEach() throws {
        try runUploaderWithTwoFilesAndOneChangeEach(withFileGroup: false)
    }

    func runUploaderWithTwoFileGroupsAndTwoFiles(withFileGroup:Bool) throws {
        let deviceUUID = Foundation.UUID().uuidString
        let fileUUID1 = Foundation.UUID().uuidString
        let fileUUID2 = Foundation.UUID().uuidString
        
        var fileGroup1: FileGroup?
        var fileGroup2: FileGroup?

        if withFileGroup {
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
        
        let exp = expectation(description: "run")
        
        runCompleted = { error in
            XCTAssert(error == nil)
            exp.fulfill()
        }
        
        try uploader.run()
        
        waitForExpectations(timeout: 10, handler: nil)
        
        guard checkCommentFile(expectedComment: comment1, deviceUUID: deviceUUID, fileUUID: fileUUID1, userId: fileIndex.userId) else {
            XCTFail()
            return
        }

        guard checkCommentFile(expectedComment: comment2, deviceUUID: deviceUUID, fileUUID: fileUUID2, userId: fileIndex.userId) else {
            XCTFail()
            return
        }
    }
    
    func testUploaderWithTwoFileGroupsAndTwoFiles() throws {
        try runUploaderWithTwoFileGroupsAndTwoFiles(withFileGroup: true)
    }
    
    func testUploaderWithNoFileGroupWithTwoFileGroupsAndTwoFiles() throws {
        try runUploaderWithTwoFileGroupsAndTwoFiles(withFileGroup: false)
    }

    // MARK: Two sharing groups
    
    func runUploaderWithTwoSharingGroupsWithASingleFileGroupInEach(withFileGroup:Bool) throws {
        let deviceUUID = Foundation.UUID().uuidString
        let fileUUID1 = Foundation.UUID().uuidString
        let fileUUID2 = Foundation.UUID().uuidString

        var fileGroup1: FileGroup?
        var fileGroup2: FileGroup?

        if withFileGroup {
            fileGroup1 = FileGroup(fileGroupUUID: Foundation.UUID().uuidString, objectType: "Foo")
            fileGroup2 = FileGroup(fileGroupUUID: Foundation.UUID().uuidString, objectType: "Foo")
        }
        
        let changeResolverName = CommentFile.changeResolverName
        
        // Do the v0 uploads.
        guard let result1 = uploadTextFile(uploadIndex: 1, uploadCount: 1, deviceUUID:deviceUUID, fileUUID: fileUUID1, fileLabel: UUID().uuidString, stringFile: .commentFile, fileGroup: fileGroup1, changeResolverName: changeResolverName),
            let sharingGroupUUID1 = result1.sharingGroupUUID else {
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
        
        guard let _ = uploadTextFile(uploadIndex: 1, uploadCount: 1, deviceUUID:deviceUUID, fileUUID: fileUUID2, addUser: .no(sharingGroupUUID: sharingGroupUUID2), fileLabel: UUID().uuidString, stringFile: .commentFile, fileGroup: fileGroup2, changeResolverName: changeResolverName) else {
            XCTFail()
            return
        }

        let comment1 = ExampleComment(messageString: "Example", id: Foundation.UUID().uuidString)
        let comment2 = ExampleComment(messageString: "Another message", id: Foundation.UUID().uuidString)

        guard let fileIndex = getFileIndex(sharingGroupUUID: sharingGroupUUID1, fileUUID: fileUUID1) else {
            XCTFail()
            return
        }
        
        guard let deferredUpload1 = createDeferredUpload(userId: fileIndex.userId, fileGroupUUID: fileGroup1?.fileGroupUUID, sharingGroupUUID: sharingGroupUUID1, status: .pendingChange),
            let deferredUploadId1 = deferredUpload1.deferredUploadId else {
            XCTFail()
            return
        }
        
        guard let deferredUpload2 = createDeferredUpload(userId: fileIndex.userId, fileGroupUUID: fileGroup2?.fileGroupUUID, sharingGroupUUID: sharingGroupUUID2, status: .pendingChange),
            let deferredUploadId2 = deferredUpload2.deferredUploadId else {
            XCTFail()
            return
        }
        
        guard let _ = createUploadForTextFile(deviceUUID: deviceUUID, fileUUID: fileUUID1, sharingGroupUUID: sharingGroupUUID1, userId: fileIndex.userId, deferredUploadId: deferredUploadId1, updateContents: comment1.updateContents, uploadCount: 1, uploadIndex: 1) else {
            XCTFail()
            return
        }
        
        guard let _ = createUploadForTextFile(deviceUUID: deviceUUID, fileUUID: fileUUID2, sharingGroupUUID: sharingGroupUUID2, userId: fileIndex.userId, deferredUploadId: deferredUploadId2, updateContents: comment2.updateContents, uploadCount: 1, uploadIndex: 1) else {
            XCTFail()
            return
        }
        
        let exp = expectation(description: "run")
        
        runCompleted = { error in
            XCTAssert(error == nil)
            exp.fulfill()
        }
        
        try uploader.run()
        
        waitForExpectations(timeout: 20, handler: nil)
        
        guard checkCommentFile(expectedComment: comment1, deviceUUID: deviceUUID, fileUUID: fileUUID1, userId: fileIndex.userId) else {
            XCTFail()
            return
        }

        guard checkCommentFile(expectedComment: comment2, deviceUUID: deviceUUID, fileUUID: fileUUID2, userId: fileIndex.userId) else {
            XCTFail()
            return
        }
    }
    
    func testUploaderWithTwoSharingGroupsWithASingleFileGroupInEach() throws {
        try runUploaderWithTwoSharingGroupsWithASingleFileGroupInEach(withFileGroup: true)
    }
    
    func testUploaderWithNoFileGroupWithTwoSharingGroupsWithASingleFileGroupInEach() throws {
        try runUploaderWithTwoSharingGroupsWithASingleFileGroupInEach(withFileGroup: false)
    }
    
    func runUploaderWithTwoSharingGroupsWithTwoFilesInOneAndOneInOtherWorks(withFileGroup: Bool) throws {
        let deviceUUID = Foundation.UUID().uuidString
        let fileUUID1 = Foundation.UUID().uuidString
        let fileUUID2 = Foundation.UUID().uuidString
        let fileUUID3 = Foundation.UUID().uuidString

        var fileGroup1: FileGroup?
        var fileGroup2: FileGroup?

        if withFileGroup {
            fileGroup1 = FileGroup(fileGroupUUID: Foundation.UUID().uuidString, objectType: "Foo")
            fileGroup2 = FileGroup(fileGroupUUID: Foundation.UUID().uuidString, objectType: "Foo")
        }

        let changeResolverName = CommentFile.changeResolverName
        
        // Do the v0 uploads.
        
        guard let result1 = uploadTextFile(uploadIndex: 1, uploadCount: 1, deviceUUID:deviceUUID, fileUUID: fileUUID1, fileLabel: UUID().uuidString, stringFile: .commentFile, fileGroup: fileGroup1, changeResolverName: changeResolverName),
            let sharingGroupUUID1 = result1.sharingGroupUUID else {
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
        
        guard let _ = uploadTextFile(uploadIndex: 1, uploadCount: 1, deviceUUID:deviceUUID, fileUUID: fileUUID2, addUser: .no(sharingGroupUUID: sharingGroupUUID2), fileLabel: UUID().uuidString, stringFile: .commentFile, fileGroup: fileGroup2, changeResolverName: changeResolverName) else {
            XCTFail()
            return
        }
        
        guard let _ = uploadTextFile(uploadIndex: 1, uploadCount: 1, deviceUUID:deviceUUID, fileUUID: fileUUID3, addUser: .no(sharingGroupUUID: sharingGroupUUID2), fileLabel: UUID().uuidString, stringFile: .commentFile, fileGroup: fileGroup2, changeResolverName: changeResolverName) else {
            XCTFail()
            return
        }
        
        let comment1 = ExampleComment(messageString: "Example", id: Foundation.UUID().uuidString)
        let comment2 = ExampleComment(messageString: "Another message", id: Foundation.UUID().uuidString)
        let comment3 = ExampleComment(messageString: "Foodbar", id: Foundation.UUID().uuidString)
        
        guard let fileIndex = getFileIndex(sharingGroupUUID: sharingGroupUUID1, fileUUID: fileUUID1) else {
            XCTFail()
            return
        }
        
        guard let deferredUpload1 = createDeferredUpload(userId: fileIndex.userId, fileGroupUUID: fileGroup1?.fileGroupUUID, sharingGroupUUID: sharingGroupUUID1, status: .pendingChange),
            let deferredUploadId1 = deferredUpload1.deferredUploadId else {
            XCTFail()
            return
        }
        
        guard let deferredUpload2 = createDeferredUpload(userId: fileIndex.userId, fileGroupUUID: fileGroup2?.fileGroupUUID, sharingGroupUUID: sharingGroupUUID2, status: .pendingChange),
            let deferredUploadId2 = deferredUpload2.deferredUploadId else {
            XCTFail()
            return
        }
        
        guard let _ = createUploadForTextFile(deviceUUID: deviceUUID, fileUUID: fileUUID1, sharingGroupUUID: sharingGroupUUID1, userId: fileIndex.userId, deferredUploadId: deferredUploadId1, updateContents: comment1.updateContents, uploadCount: 1, uploadIndex: 1) else {
            XCTFail()
            return
        }
        
        guard let _ = createUploadForTextFile(deviceUUID: deviceUUID, fileUUID: fileUUID2, sharingGroupUUID: sharingGroupUUID2, userId: fileIndex.userId, deferredUploadId: deferredUploadId2, updateContents: comment2.updateContents, uploadCount: 1, uploadIndex: 1) else {
            XCTFail()
            return
        }
        
        guard let _ = createUploadForTextFile(deviceUUID: deviceUUID, fileUUID: fileUUID3, sharingGroupUUID: sharingGroupUUID2, userId: fileIndex.userId, deferredUploadId: deferredUploadId2, updateContents: comment3.updateContents, uploadCount: 1, uploadIndex: 1) else {
            XCTFail()
            return
        }
        
        let exp = expectation(description: "run")
        
        runCompleted = { error in
            XCTAssert(error == nil)
            exp.fulfill()
        }
        
        try uploader.run()
        
        // This takes appreciable real time. It has to download two files, upload them both too, and delete the prior version.
        waitForExpectations(timeout: 20, handler: nil)
        
        guard checkCommentFile(expectedComment: comment1, deviceUUID: deviceUUID, fileUUID: fileUUID1, userId: fileIndex.userId) else {
            XCTFail()
            return
        }

        guard checkCommentFile(expectedComment: comment2, deviceUUID: deviceUUID, fileUUID: fileUUID2, userId: fileIndex.userId) else {
            XCTFail()
            return
        }
        
        guard checkCommentFile(expectedComment: comment3, deviceUUID: deviceUUID, fileUUID: fileUUID3, userId: fileIndex.userId) else {
            XCTFail()
            return
        }
    }
    
    func testUploaderWithTwoSharingGroupsWithTwoFilesInOneAndOneInOtherWorks() throws {
        try runUploaderWithTwoSharingGroupsWithTwoFilesInOneAndOneInOtherWorks(withFileGroup: true)
    }
    
    func testUploaderWithNoFileGroupWithTwoSharingGroupsWithTwoFilesInOneAndOneInOtherWorks() throws {
        try runUploaderWithTwoSharingGroupsWithTwoFilesInOneAndOneInOtherWorks(withFileGroup: false)
    }
}

extension UploaderFileChangeTests: UploaderDelegate {
    func run(completed: UploaderProtocol, error: Swift.Error?) {
        runCompleted?(error)
    }
}
