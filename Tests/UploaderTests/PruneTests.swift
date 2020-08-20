
import LoggerAPI
@testable import Server
@testable import TestsCommon
import KituraNet
import XCTest
import Foundation
import ServerShared
import ChangeResolvers
import Credentials

class PruneTests: ServerTestCase, UploaderCommon {
    var accountManager: AccountManager!
    var uploader: Uploader!
    var runCompleted:((Swift.Error?)->())?
    
    override func setUp() {
        super.setUp()
        
        accountManager = AccountManager(userRepository: UserRepository(db))
        accountManager.setupAccounts(credentials: Credentials())
        let resolverManager = ChangeResolverManager()

        guard let services = Services(accountManager: accountManager, changeResolverManager: resolverManager) else {
            XCTFail()
            return
        }
        
        do {
            try resolverManager.setupResolvers()
            uploader = try Uploader(services: services)
        } catch let error {
            XCTFail("\(error)")
            return
        }
        
        uploader.delegate = self
        runCompleted = nil
    }

    // Pruning: Remove file change uploads (DeferredUpload, Upload's) from the database corresponding to  deletions.

    func testPruneWithNoDeferredUploads() throws {
        guard uploader.pruneFileUploads(deferredFileDeletions: []) else {
            XCTFail()
            return
        }
    }
    
    // The upload change and deletion are for the same file.
    func runPruneWithOneUploadChangeAndOneFileDeletion(withFileGroup: Bool) throws {
        let fileUUID1 = Foundation.UUID().uuidString
        let deviceUUID = Foundation.UUID().uuidString
        let changeResolverName = CommentFile.changeResolverName
        
        guard let deferredCount = DeferredUploadRepository(db).count(),
            let uploadCount = UploadRepository(db).count() else {
            XCTFail()
            return
        }

        var fileGroupUUID: String?
        if withFileGroup {
            fileGroupUUID = Foundation.UUID().uuidString
        }
        
        guard let result1 = uploadTextFile(uploadIndex: 1, uploadCount: 1, deviceUUID:deviceUUID, fileUUID: fileUUID1, stringFile: .commentFile, fileGroupUUID:fileGroupUUID, changeResolverName: changeResolverName),
            let sharingGroupUUID = result1.sharingGroupUUID else {
            XCTFail()
            return
        }
        
        guard let userId = result1.uploadingUserId else {
            XCTFail()
            return
        }

        let comment1 = ExampleComment(messageString: "Example", id: Foundation.UUID().uuidString)
        
        // Set up the upload change
        guard let deferredUpload1 = createDeferredUpload(userId: userId, fileGroupUUID: fileGroupUUID, sharingGroupUUID: sharingGroupUUID, status: .pendingChange),
            let deferredUploadId1 = deferredUpload1.deferredUploadId else {
            XCTFail()
            return
        }

        // vN UploadRequest's, for the real endpoint don't allow fileGroupUUID's, but the resultant Upload record (that we're faking), do have a fileGroupUUID.
        guard let _ = createUploadForTextFile(deviceUUID: deviceUUID, fileUUID: fileUUID1, fileGroupUUID: fileGroupUUID, sharingGroupUUID: sharingGroupUUID, userId: userId, deferredUploadId:deferredUploadId1, updateContents: comment1.updateContents, uploadCount: 1, uploadIndex: 1, state: .vNUploadFileChange) else {
            XCTFail()
            return
        }
        
        // Set up the upload deletion
        guard let deferredUpload2 = createDeferredUpload(userId: userId, fileGroupUUID: fileGroupUUID, sharingGroupUUID: sharingGroupUUID, status: .pendingDeletion),
            let deferredUploadId2 = deferredUpload2.deferredUploadId else {
            XCTFail()
            return
        }
            
        // Upload deletions only have a DeferredUpload record when there is a file group.
        if !withFileGroup {
            guard let _ = createUploadForTextFile(deviceUUID: deviceUUID, fileUUID: fileUUID1, sharingGroupUUID: sharingGroupUUID, userId: userId, deferredUploadId:deferredUploadId2, updateContents: comment1.updateContents, uploadCount: 1, uploadIndex: 1, state: .deleteSingleFile) else {
                XCTFail()
                return
            }
        }
        
        guard uploader.pruneFileUploads(deferredFileDeletions: [deferredUpload2]) else {
            XCTFail()
            return
        }
        
        XCTAssert(deferredCount + 1 == DeferredUploadRepository(db).count(), "\(deferredCount) + 1 != \(String(describing: DeferredUploadRepository(db).count()))")
        
        if withFileGroup {
            // The upload deletion has no Upload record
            // The upload change Upload record has been removed.
            XCTAssert(uploadCount == UploadRepository(db).count(), "\(uploadCount) != \(String(describing: UploadRepository(db).count()))")
        }
        else {
            // The upload deletion has an Upload record
            // The upload change Upload record has been removed.
            XCTAssert(uploadCount + 1 == UploadRepository(db).count(), "\(uploadCount) + 1 != \(String(describing: UploadRepository(db).count()))")
        }
    }
    
    func testPruneWithOneUploadChangeAndOneFileDeletionWithFileGroup() throws {
        try runPruneWithOneUploadChangeAndOneFileDeletion(withFileGroup: true)
    }

    func testPruneWithOneUploadChangeAndOneFileDeletionWithoutFileGroup() throws {
        try runPruneWithOneUploadChangeAndOneFileDeletion(withFileGroup: false)
    }
}

extension PruneTests: UploaderDelegate {
    func run(completed: UploaderProtocol, error: Swift.Error?) {
        runCompleted?(error)
    }
}
