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
    }
}

extension UploaderTests: UploaderDelegate {
    func run(completed: Uploader, error: Swift.Error?) {
        runCompleted?(error)
    }
}
