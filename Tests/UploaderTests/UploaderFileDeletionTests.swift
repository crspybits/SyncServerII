
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

class UploaderFileDeletionTests: ServerTestCase, UploaderCommon {
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
    
    func runDeletionOfFile(withFileGroup:Bool) throws {
        let deviceUUID = Foundation.UUID().uuidString
        let fileUUID = Foundation.UUID().uuidString
        
        var fileGroupUUID: String?
        if withFileGroup {
            fileGroupUUID = Foundation.UUID().uuidString
        }
        
        guard let deferredCount = DeferredUploadRepository(db).count() else {
            XCTFail()
            return
        }
        
        guard let uploadCount = UploadRepository(db).count() else {
            XCTFail()
            return
        }

        // Do the v0 upload.
        guard let result = uploadTextFile(uploadIndex: 1, uploadCount: 1, deviceUUID:deviceUUID, fileUUID: fileUUID, stringFile: .commentFile, fileGroupUUID: fileGroupUUID),
            let sharingGroupUUID = result.sharingGroupUUID else {
            XCTFail()
            return
        }
        
        guard let userId = result.uploadingUserId else {
            XCTFail()
            return
        }
        
        // Simulate an upload deletion request for file

        guard let deferredUpload = createDeferredUpload(fileGroupUUID: fileGroupUUID, sharingGroupUUID: sharingGroupUUID, status: .pendingDeletion),
            let deferredUploadId = deferredUpload.deferredUploadId else {
            XCTFail()
            return
        }
        
        if fileGroupUUID == nil {
            guard let _ = createUploadForTextFile(deviceUUID: deviceUUID, fileUUID: fileUUID, fileGroupUUID: fileGroupUUID, sharingGroupUUID: sharingGroupUUID, userId: userId, deferredUploadId: deferredUploadId, state: .deleteSingleFile) else {
                XCTFail()
                return
            }
        }
        
        let exp = expectation(description: "run")
        
        runCompleted = { error in
            XCTAssert(error == nil)
            exp.fulfill()
        }
        
        try uploader.run()
        
        waitForExpectations(timeout: 10, handler: nil)
        
        XCTAssert(deferredCount == DeferredUploadRepository(db).count())
        XCTAssert(uploadCount == UploadRepository(db).count(), "\(uploadCount) != \(String(describing: UploadRepository(db).count())))")
        
        guard let fileIndex = getFileIndex(sharingGroupUUID: sharingGroupUUID, fileUUID: fileUUID) else {
            XCTFail()
            return
        }
        
        let found = try fileIsInCloudStorage(fileIndex: fileIndex)
        XCTAssert(!found)
    }
    
    func testDeletionOfFileWithNoFileGroup() throws {
        try runDeletionOfFile(withFileGroup:false)
    }
    
    func testDeletionOfOneFileWithFileGroup() throws {
        try runDeletionOfFile(withFileGroup:true)
    }
    
    func runDeletionOfTwoFiles(withFileGroup:Bool) throws {
        let deviceUUID = Foundation.UUID().uuidString
        let fileUUID1 = Foundation.UUID().uuidString
        let fileUUID2 = Foundation.UUID().uuidString

        var fileGroupUUID: String?
        if withFileGroup {
            fileGroupUUID = Foundation.UUID().uuidString
        }
        
        guard let deferredCount = DeferredUploadRepository(db).count() else {
            XCTFail()
            return
        }
        
        guard let uploadCount = UploadRepository(db).count() else {
            XCTFail()
            return
        }

        // Do the v0 uploads.
        guard let result = uploadTextFile(uploadIndex: 1, uploadCount: 1, deviceUUID:deviceUUID, fileUUID: fileUUID1, stringFile: .commentFile, fileGroupUUID: fileGroupUUID),
            let sharingGroupUUID = result.sharingGroupUUID else {
            XCTFail()
            return
        }
        
        guard let userId = result.uploadingUserId else {
            XCTFail()
            return
        }
        
        guard let _ = uploadTextFile(uploadIndex: 1, uploadCount: 1, deviceUUID:deviceUUID, fileUUID: fileUUID2, addUser: .no(sharingGroupUUID: sharingGroupUUID), stringFile: .commentFile, fileGroupUUID: fileGroupUUID) else {
            XCTFail()
            return
        }
        
        // Simulate an upload deletion request for files

        guard let deferredUpload1 = createDeferredUpload(fileGroupUUID: fileGroupUUID, sharingGroupUUID: sharingGroupUUID, status: .pendingDeletion),
            let deferredUploadId1 = deferredUpload1.deferredUploadId else {
            XCTFail()
            return
        }
        
        if fileGroupUUID == nil {
            guard let _ = createUploadForTextFile(deviceUUID: deviceUUID, fileUUID: fileUUID1, fileGroupUUID: fileGroupUUID, sharingGroupUUID: sharingGroupUUID, userId: userId, deferredUploadId: deferredUploadId1, state: .deleteSingleFile) else {
                XCTFail()
                return
            }
        
            guard let deferredUpload2 = createDeferredUpload(fileGroupUUID: fileGroupUUID, sharingGroupUUID: sharingGroupUUID, status: .pendingDeletion),
                let deferredUploadId2 = deferredUpload2.deferredUploadId else {
                XCTFail()
                return
            }
        
            guard let _ = createUploadForTextFile(deviceUUID: deviceUUID, fileUUID: fileUUID2, fileGroupUUID: fileGroupUUID, sharingGroupUUID: sharingGroupUUID, userId: userId, deferredUploadId: deferredUploadId2, state: .deleteSingleFile) else {
                XCTFail()
                return
            }
        }
        
        let exp = expectation(description: "run")
        
        runCompleted = { error in
            XCTAssert(error == nil)
            exp.fulfill()
        }
        
        try uploader.run()
        
        waitForExpectations(timeout: 10, handler: nil)
        
        XCTAssert(deferredCount == DeferredUploadRepository(db).count())
        XCTAssert(uploadCount == UploadRepository(db).count(), "\(uploadCount) != \(String(describing: UploadRepository(db).count())))")
        

        guard let fileIndex1 = getFileIndex(sharingGroupUUID: sharingGroupUUID, fileUUID: fileUUID1) else {
            XCTFail()
            return
        }
        
        guard let fileIndex2 = getFileIndex(sharingGroupUUID: sharingGroupUUID, fileUUID: fileUUID2) else {
            XCTFail()
            return
        }
        
        let found1 = try fileIsInCloudStorage(fileIndex: fileIndex1)
        XCTAssert(!found1)
        let found2 = try fileIsInCloudStorage(fileIndex: fileIndex2)
        XCTAssert(!found2)
    }
    
    func testDeletionOfTwoFilesWithNoFileGroup() throws {
        try runDeletionOfTwoFiles(withFileGroup:false)
    }
    
    func testDeletionOfTwoFilesWithFileGroup() throws {
        try runDeletionOfTwoFiles(withFileGroup:true)
    }
    
    func testDeletionOfFileWithFileGroupAndFileWithoutFileGroup() throws {
        let deviceUUID = Foundation.UUID().uuidString
        let fileUUID1 = Foundation.UUID().uuidString // has file group
        let fileUUID2 = Foundation.UUID().uuidString // has no file group

        let fileGroupUUID = Foundation.UUID().uuidString

        guard let deferredCount = DeferredUploadRepository(db).count() else {
            XCTFail()
            return
        }
        
        guard let uploadCount = UploadRepository(db).count() else {
            XCTFail()
            return
        }

        // Do the v0 uploads.
        guard let result = uploadTextFile(uploadIndex: 1, uploadCount: 1, deviceUUID:deviceUUID, fileUUID: fileUUID1, stringFile: .commentFile, fileGroupUUID: fileGroupUUID),
            let sharingGroupUUID = result.sharingGroupUUID else {
            XCTFail()
            return
        }
        
        guard let userId = result.uploadingUserId else {
            XCTFail()
            return
        }
        
        guard let _ = uploadTextFile(uploadIndex: 1, uploadCount: 1, deviceUUID:deviceUUID, fileUUID: fileUUID2, addUser: .no(sharingGroupUUID: sharingGroupUUID), stringFile: .commentFile) else {
            XCTFail()
            return
        }
        
        // Simulate an upload deletion request for files

        // For fileUUID, just use its file group in a DeferredUpload; don't need an Upload record.
        guard let _ = createDeferredUpload(fileGroupUUID: fileGroupUUID, sharingGroupUUID: sharingGroupUUID, status: .pendingDeletion) else {
            XCTFail()
            return
        }
    
        guard let deferredUpload2 = createDeferredUpload(sharingGroupUUID: sharingGroupUUID, status: .pendingDeletion),
            let deferredUploadId2 = deferredUpload2.deferredUploadId else {
            XCTFail()
            return
        }
    
        guard let _ = createUploadForTextFile(deviceUUID: deviceUUID, fileUUID: fileUUID2, sharingGroupUUID: sharingGroupUUID, userId: userId, deferredUploadId: deferredUploadId2, state: .deleteSingleFile) else {
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
        
        XCTAssert(deferredCount == DeferredUploadRepository(db).count())
        XCTAssert(uploadCount == UploadRepository(db).count(), "\(uploadCount) != \(String(describing: UploadRepository(db).count())))")

        guard let fileIndex1 = getFileIndex(sharingGroupUUID: sharingGroupUUID, fileUUID: fileUUID1) else {
            XCTFail()
            return
        }
        
        guard let fileIndex2 = getFileIndex(sharingGroupUUID: sharingGroupUUID, fileUUID: fileUUID2) else {
            XCTFail()
            return
        }
        
        let found1 = try fileIsInCloudStorage(fileIndex: fileIndex1)
        XCTAssert(!found1)
        let found2 = try fileIsInCloudStorage(fileIndex: fileIndex2)
        XCTAssert(!found2)
    }
}

extension UploaderFileDeletionTests: UploaderDelegate {
    func run(completed: UploaderProtocol, error: Swift.Error?) {
        runCompleted?(error)
    }
}
