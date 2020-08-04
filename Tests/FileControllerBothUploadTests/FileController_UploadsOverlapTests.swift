
import XCTest
@testable import Server
@testable import TestsCommon
import LoggerAPI
import HeliumLogger
import Foundation
import ServerShared
import ChangeResolvers
import Credentials

class FileController_UploadsOverlapTests: ServerTestCase, UploaderCommon {
    var accountManager: AccountManager!
    
    override func setUp() {
        super.setUp()
        
        accountManager = AccountManager(userRepository: UserRepository(db))
        let credentials = Credentials()
        accountManager.setupAccounts(credentials: credentials)
    }
    
    // Upload file change, and an upload deletion for the same file.
    func runOneUploadFileChangeAndThenOneUploadDeletion(withFileGroup: Bool) throws {
        let fileUUID1 = Foundation.UUID().uuidString
        let deviceUUID = Foundation.UUID().uuidString
        let changeResolverName = CommentFile.changeResolverName
        
        guard let deferredCount = DeferredUploadRepository(db).count() else {
            XCTFail()
            return
        }
        
        guard let uploadCount = UploadRepository(db).count() else {
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

        guard let deferredUpload = createDeferredUpload(fileGroupUUID: fileGroupUUID, sharingGroupUUID: sharingGroupUUID, status: .pendingChange),
            let deferredUploadId = deferredUpload.deferredUploadId else {
            XCTFail()
            return
        }
            
        guard let _ = createUploadForTextFile(deviceUUID: deviceUUID, fileUUID: fileUUID1, sharingGroupUUID: sharingGroupUUID, userId: userId, deferredUploadId:deferredUploadId, updateContents: comment1.updateContents, uploadCount: 1, uploadIndex: 1, state: .vNUploadFileChange) else {
            XCTFail()
            return
        }
        
        let uploadDeletionRequest = UploadDeletionRequest()
        uploadDeletionRequest.sharingGroupUUID = sharingGroupUUID
        if withFileGroup {
            uploadDeletionRequest.fileGroupUUID = fileGroupUUID
        }
        else {
            uploadDeletionRequest.fileUUID = fileUUID1
        }
        
        guard let _ = uploadDeletion(uploadDeletionRequest: uploadDeletionRequest, deviceUUID: deviceUUID, addUser: false) else {
            XCTFail()
            return
        }
        
        guard let fileIndex1 = getFileIndex(sharingGroupUUID: sharingGroupUUID, fileUUID: fileUUID1) else {
            XCTFail()
            return
        }
        
        // Expectation: File should be deleted.
        let found1 = try fileIsInCloudStorage(fileIndex: fileIndex1)
        XCTAssert(!found1)
        
        XCTAssert(deferredCount == DeferredUploadRepository(db).count())
        XCTAssert(uploadCount == UploadRepository(db).count(), "\(uploadCount) != \(String(describing: UploadRepository(db).count())))")
    }

    func testOneUploadFileChangeAndThenOneUploadDeletionWithoutFileGroup() throws {
        try runOneUploadFileChangeAndThenOneUploadDeletion(withFileGroup: false)
    }

    func testOneUploadFileChangeAndThenOneUploadDeletionWithFileGroup() throws {
        try runOneUploadFileChangeAndThenOneUploadDeletion(withFileGroup: true)
    }
}
