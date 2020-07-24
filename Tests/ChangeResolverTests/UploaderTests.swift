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

class UploaderTests: ServerTestCase, UploaderCommon {
    var accountManager: AccountManager!
    var uploader: Uploader!
    var runCompleted:((Swift.Error?)->())?
    
    override func setUp() {
        super.setUp()
        
        accountManager = AccountManager(userRepository: UserRepository(db))
        accountManager.setupAccounts(credentials: Credentials())
        
        let resolverManager = ChangeResolverManager()
        do {
            try resolverManager.setupResolvers()
            uploader = try Uploader(resolverManager: resolverManager, accountManager: accountManager)
        } catch let error {
            XCTFail("\(error)")
            return
        }
        
        uploader.delegate = self
        runCompleted = nil
    }
    
    // MARK: One sharing group

    func testUploaderWithASingleFileWithOneChange() throws {
        let deviceUUID = Foundation.UUID().uuidString
        let fileUUID = Foundation.UUID().uuidString
        let fileGroupUUID = Foundation.UUID().uuidString
        let changeResolverName = CommentFile.changeResolverName

        // Do the v0 upload.
        guard let result = uploadTextFile(uploadIndex: 1, uploadCount: 1, deviceUUID:deviceUUID, fileUUID: fileUUID, stringFile: .commentFile, fileGroupUUID: fileGroupUUID, changeResolverName: changeResolverName),
            let sharingGroupUUID = result.sharingGroupUUID else {
            XCTFail()
            return
        }
        
        let comment = ExampleComment(messageString: "Example", id: Foundation.UUID().uuidString)
        
        guard let fileIndex = getFileIndex(sharingGroupUUID: sharingGroupUUID, fileUUID: fileUUID) else {
            XCTFail()
            return
        }
        
        guard let deferredUpload = createDeferredUpload(fileGroupUUID: fileGroupUUID, sharingGroupUUID: sharingGroupUUID),
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
    
    func testUploaderWithASingleFileAndTwoChanges() throws {
        let deviceUUID = Foundation.UUID().uuidString
        let fileUUID = Foundation.UUID().uuidString
        let fileGroupUUID = Foundation.UUID().uuidString

        let changeResolverName = CommentFile.changeResolverName

        // Do the v0 upload.
        guard let result = uploadTextFile(uploadIndex: 1, uploadCount: 1, deviceUUID:deviceUUID, fileUUID: fileUUID, stringFile: .commentFile, fileGroupUUID: fileGroupUUID, changeResolverName: changeResolverName),
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
        
        guard let deferredUpload1 = createDeferredUpload(fileGroupUUID: fileGroupUUID, sharingGroupUUID: sharingGroupUUID),
            let deferredUploadId1 = deferredUpload1.deferredUploadId else {
            XCTFail()
            return
        }
        
        guard let deferredUpload2 = createDeferredUpload(fileGroupUUID: fileGroupUUID, sharingGroupUUID: sharingGroupUUID),
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

    func testUploaderWithTwoFilesAndOneChangeEach() throws {
        let deviceUUID = Foundation.UUID().uuidString
        let fileUUID1 = Foundation.UUID().uuidString
        let fileUUID2 = Foundation.UUID().uuidString
        let fileGroupUUID = Foundation.UUID().uuidString

        let changeResolverName = CommentFile.changeResolverName

        // Do the v0 uploads.
        guard let result1 = uploadTextFile(uploadIndex: 1, uploadCount: 1, deviceUUID:deviceUUID, fileUUID: fileUUID1, stringFile: .commentFile, fileGroupUUID: fileGroupUUID, changeResolverName: changeResolverName),
            let sharingGroupUUID = result1.sharingGroupUUID else {
            XCTFail()
            return
        }
        
        guard let _ = uploadTextFile(uploadIndex: 1, uploadCount: 1, deviceUUID:deviceUUID, fileUUID: fileUUID2, addUser: .no(sharingGroupUUID: sharingGroupUUID), stringFile: .commentFile, fileGroupUUID: fileGroupUUID, changeResolverName: changeResolverName) else {
            XCTFail()
            return
        }
        
        let comment1 = ExampleComment(messageString: "Example", id: Foundation.UUID().uuidString)
        let comment2 = ExampleComment(messageString: "Another message", id: Foundation.UUID().uuidString)
        
        guard let fileIndex = getFileIndex(sharingGroupUUID: sharingGroupUUID, fileUUID: fileUUID1) else {
            XCTFail()
            return
        }
        
        guard let deferredUpload1 = createDeferredUpload(fileGroupUUID: fileGroupUUID, sharingGroupUUID: sharingGroupUUID),
            let deferredUploadId1 = deferredUpload1.deferredUploadId else {
            XCTFail()
            return
        }
        
        guard let deferredUpload2 = createDeferredUpload(fileGroupUUID: fileGroupUUID, sharingGroupUUID: sharingGroupUUID),
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
        let deviceUUID = Foundation.UUID().uuidString
        let fileUUID1 = Foundation.UUID().uuidString
        let fileUUID2 = Foundation.UUID().uuidString
        let fileGroupUUID1 = Foundation.UUID().uuidString
        let fileGroupUUID2 = Foundation.UUID().uuidString
        let changeResolverName = CommentFile.changeResolverName

        // Do the v0 uploads.
        guard let result1 = uploadTextFile(uploadIndex: 1, uploadCount: 1, deviceUUID:deviceUUID, fileUUID: fileUUID1, stringFile: .commentFile, fileGroupUUID: fileGroupUUID1, changeResolverName: changeResolverName),
            let sharingGroupUUID = result1.sharingGroupUUID else {
            XCTFail()
            return
        }
        
        guard let _ = uploadTextFile(uploadIndex: 1, uploadCount: 1, deviceUUID:deviceUUID, fileUUID: fileUUID2, addUser: .no(sharingGroupUUID: sharingGroupUUID), stringFile: .commentFile, fileGroupUUID: fileGroupUUID2, changeResolverName: changeResolverName) else {
            XCTFail()
            return
        }
        
        let comment1 = ExampleComment(messageString: "Example", id: Foundation.UUID().uuidString)
        let comment2 = ExampleComment(messageString: "Another message", id: Foundation.UUID().uuidString)
        
        guard let fileIndex = getFileIndex(sharingGroupUUID: sharingGroupUUID, fileUUID: fileUUID1) else {
            XCTFail()
            return
        }

        guard let deferredUpload1 = createDeferredUpload(fileGroupUUID: fileGroupUUID1, sharingGroupUUID: sharingGroupUUID),
            let deferredUploadId1 = deferredUpload1.deferredUploadId else {
            XCTFail()
            return
        }
        
        guard let deferredUpload2 = createDeferredUpload(fileGroupUUID: fileGroupUUID2, sharingGroupUUID: sharingGroupUUID),
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

    // MARK: Two sharing groups
    
    func testUploaderWithTwoSharingGroupsWithASingleFileGroupInEach() throws {
        let deviceUUID = Foundation.UUID().uuidString
        let fileUUID1 = Foundation.UUID().uuidString
        let fileUUID2 = Foundation.UUID().uuidString
        let fileGroupUUID1 = Foundation.UUID().uuidString
        let fileGroupUUID2 = Foundation.UUID().uuidString
        let changeResolverName = CommentFile.changeResolverName
        
        // Do the v0 uploads.
        guard let result1 = uploadTextFile(uploadIndex: 1, uploadCount: 1, deviceUUID:deviceUUID, fileUUID: fileUUID1, stringFile: .commentFile, fileGroupUUID: fileGroupUUID1, changeResolverName: changeResolverName),
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
        
        guard let _ = uploadTextFile(uploadIndex: 1, uploadCount: 1, deviceUUID:deviceUUID, fileUUID: fileUUID2, addUser: .no(sharingGroupUUID: sharingGroupUUID2), stringFile: .commentFile, fileGroupUUID: fileGroupUUID2, changeResolverName: changeResolverName) else {
            XCTFail()
            return
        }

        let comment1 = ExampleComment(messageString: "Example", id: Foundation.UUID().uuidString)
        let comment2 = ExampleComment(messageString: "Another message", id: Foundation.UUID().uuidString)

        guard let fileIndex = getFileIndex(sharingGroupUUID: sharingGroupUUID1, fileUUID: fileUUID1) else {
            XCTFail()
            return
        }
        
        guard let deferredUpload1 = createDeferredUpload(fileGroupUUID: fileGroupUUID1, sharingGroupUUID: sharingGroupUUID1),
            let deferredUploadId1 = deferredUpload1.deferredUploadId else {
            XCTFail()
            return
        }
        
        guard let deferredUpload2 = createDeferredUpload(fileGroupUUID: fileGroupUUID2, sharingGroupUUID: sharingGroupUUID2),
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
    
    func testUploaderWithTwoSharingGroupsWithTwoFilesInOneAndOneInOther() throws {
        let deviceUUID = Foundation.UUID().uuidString
        let fileUUID1 = Foundation.UUID().uuidString
        let fileUUID2 = Foundation.UUID().uuidString
        let fileUUID3 = Foundation.UUID().uuidString
        let fileGroupUUID1 = Foundation.UUID().uuidString
        let fileGroupUUID2 = Foundation.UUID().uuidString

        let changeResolverName = CommentFile.changeResolverName
        
        // Do the v0 uploads.
        guard let result1 = uploadTextFile(uploadIndex: 1, uploadCount: 1, deviceUUID:deviceUUID, fileUUID: fileUUID1, stringFile: .commentFile, fileGroupUUID: fileGroupUUID1, changeResolverName: changeResolverName),
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
        
        guard let _ = uploadTextFile(uploadIndex: 1, uploadCount: 1, deviceUUID:deviceUUID, fileUUID: fileUUID2, addUser: .no(sharingGroupUUID: sharingGroupUUID2), stringFile: .commentFile, fileGroupUUID: fileGroupUUID2, changeResolverName: changeResolverName) else {
            XCTFail()
            return
        }
        
        guard let _ = uploadTextFile(uploadIndex: 1, uploadCount: 1, deviceUUID:deviceUUID, fileUUID: fileUUID3, addUser: .no(sharingGroupUUID: sharingGroupUUID2), stringFile: .commentFile, fileGroupUUID: fileGroupUUID2, changeResolverName: changeResolverName) else {
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
        
        guard let deferredUpload1 = createDeferredUpload(fileGroupUUID: fileGroupUUID1, sharingGroupUUID: sharingGroupUUID1),
            let deferredUploadId1 = deferredUpload1.deferredUploadId else {
            XCTFail()
            return
        }
        
        guard let deferredUpload2 = createDeferredUpload(fileGroupUUID: fileGroupUUID2, sharingGroupUUID: sharingGroupUUID2),
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
        
        waitForExpectations(timeout: 10, handler: nil)
        
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
    
    // MARK: nil fileGroupUUID in some sharing groups.
}

extension UploaderTests: UploaderDelegate {
    func run(completed: UploaderProtocol, error: Swift.Error?) {
        runCompleted?(error)
    }
}
