
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
            
        guard let _ = createUploadForTextFile(deviceUUID: deviceUUID, fileUUID: fileUUID1, fileGroupUUID: fileGroupUUID, sharingGroupUUID: sharingGroupUUID,  userId: userId, deferredUploadId:deferredUploadId, updateContents: comment1.updateContents, uploadCount: 1, uploadIndex: 1, state: .vNUploadFileChange) else {
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
    
    func runUploadChange(withDeletionBefore:Bool) throws {
        let fileUUID = Foundation.UUID().uuidString
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
                
        guard let result1 = uploadTextFile(uploadIndex: 1, uploadCount: 1, deviceUUID:deviceUUID, fileUUID: fileUUID, stringFile: .commentFile, changeResolverName: changeResolverName),
            let sharingGroupUUID = result1.sharingGroupUUID else {
            XCTFail()
            return
        }
        
        if withDeletionBefore {
            let uploadDeletionRequest = UploadDeletionRequest()
            uploadDeletionRequest.sharingGroupUUID = sharingGroupUUID
            uploadDeletionRequest.fileUUID = fileUUID
            
            guard let _ = uploadDeletion(uploadDeletionRequest: uploadDeletionRequest, deviceUUID: deviceUUID, addUser: false) else {
                XCTFail()
                return
            }
        }
        
        let comment1 = ExampleComment(messageString: "Example", id: Foundation.UUID().uuidString)
        let result2 = uploadTextFile(uploadIndex: 1, uploadCount: 1, deviceUUID:deviceUUID, fileUUID: fileUUID, addUser: .no(sharingGroupUUID: sharingGroupUUID), errorExpected: withDeletionBefore, dataToUpload: comment1.updateContents)
        
        if withDeletionBefore {
            XCTAssert(result2 == nil, "\(String(describing: result2))")
        }
        else {
            XCTAssert(result2 != nil, "\(String(describing: result2))")
        }
        
        guard let fileIndex1 = getFileIndex(sharingGroupUUID: sharingGroupUUID, fileUUID: fileUUID) else {
            XCTFail()
            return
        }
        
        let found1 = try fileIsInCloudStorage(fileIndex: fileIndex1)
        
        if withDeletionBefore {
            XCTAssert(!found1)
        }
        else {
            XCTAssert(found1)
        }
        
        XCTAssert(deferredCount == DeferredUploadRepository(db).count())
        XCTAssert(uploadCount == UploadRepository(db).count(), "\(uploadCount) != \(String(describing: UploadRepository(db).count())))")
    }
    
    func testUploadChangeAfterDeletionCompletedFails() throws {
        try runUploadChange(withDeletionBefore: true)
    }

    func testUploadChangeWithNoPriorDeletionWorks() throws {
        try runUploadChange(withDeletionBefore: false)
    }
    
    func runTwoUploadFileChangesAndThenOneUploadDeletionForSameFile(withFileGroup: Bool) throws {
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
        let comment2 = ExampleComment(messageString: "Example", id: Foundation.UUID().uuidString)
        
        guard let deferredUpload1 = createDeferredUpload(fileGroupUUID: fileGroupUUID, sharingGroupUUID: sharingGroupUUID, status: .pendingChange),
            let deferredUploadId1 = deferredUpload1.deferredUploadId else {
            XCTFail()
            return
        }
            
        guard let _ = createUploadForTextFile(deviceUUID: deviceUUID, fileUUID: fileUUID1, fileGroupUUID: fileGroupUUID, sharingGroupUUID: sharingGroupUUID, userId: userId, deferredUploadId:deferredUploadId1, updateContents: comment1.updateContents, uploadCount: 1, uploadIndex: 1, state: .vNUploadFileChange) else {
            XCTFail()
            return
        }
        
        guard let deferredUpload2 = createDeferredUpload(fileGroupUUID: fileGroupUUID, sharingGroupUUID: sharingGroupUUID, status: .pendingChange),
            let deferredUploadId2 = deferredUpload2.deferredUploadId else {
            XCTFail()
            return
        }
            
        guard let _ = createUploadForTextFile(deviceUUID: deviceUUID, fileUUID: fileUUID1, fileGroupUUID: fileGroupUUID, sharingGroupUUID: sharingGroupUUID, userId: userId, deferredUploadId:deferredUploadId2, updateContents: comment2.updateContents, uploadCount: 1, uploadIndex: 1, state: .vNUploadFileChange) else {
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
    
    func testRunTwoUploadFileChangesAndThenOneUploadDeletionForSameFileWithFileGroup() throws {
        try runTwoUploadFileChangesAndThenOneUploadDeletionForSameFile(withFileGroup: true)
    }
    
    func testRunTwoUploadFileChangesAndThenOneUploadDeletionForSameFileWithoutFileGroup() throws {
        try runTwoUploadFileChangesAndThenOneUploadDeletionForSameFile(withFileGroup: false)
    }
    
    func runTwoChangesAndThenOneDeletionForSameFilePlusOtherUploadChange(withFileGroup: Bool) throws {
        let fileUUID1 = Foundation.UUID().uuidString
        let fileUUID2 = Foundation.UUID().uuidString
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
        
        // Explicitly not including this one in file group because we're going to upload a change for it, which we don't want removed with the other file group.
        guard let _ = uploadTextFile(uploadIndex: 1, uploadCount: 1, deviceUUID:deviceUUID, fileUUID: fileUUID2, addUser: .no(sharingGroupUUID: sharingGroupUUID), stringFile: .commentFile, changeResolverName: changeResolverName) else {
            XCTFail()
            return
        }
        
        guard let userId = result1.uploadingUserId else {
            XCTFail()
            return
        }
        
        let comment1 = ExampleComment(messageString: "Example", id: Foundation.UUID().uuidString)
        let comment2 = ExampleComment(messageString: "Example", id: Foundation.UUID().uuidString)
        let comment3 = ExampleComment(messageString: "Example", id: Foundation.UUID().uuidString)
        
        guard let deferredUpload1 = createDeferredUpload(fileGroupUUID: fileGroupUUID, sharingGroupUUID: sharingGroupUUID, status: .pendingChange),
            let deferredUploadId1 = deferredUpload1.deferredUploadId else {
            XCTFail()
            return
        }
            
        guard let _ = createUploadForTextFile(deviceUUID: deviceUUID, fileUUID: fileUUID1, fileGroupUUID: fileGroupUUID, sharingGroupUUID: sharingGroupUUID, userId: userId, deferredUploadId:deferredUploadId1, updateContents: comment1.updateContents, uploadCount: 1, uploadIndex: 1, state: .vNUploadFileChange) else {
            XCTFail()
            return
        }
        
        guard let deferredUpload2 = createDeferredUpload(fileGroupUUID: fileGroupUUID, sharingGroupUUID: sharingGroupUUID, status: .pendingChange),
            let deferredUploadId2 = deferredUpload2.deferredUploadId else {
            XCTFail()
            return
        }
            
        guard let _ = createUploadForTextFile(deviceUUID: deviceUUID, fileUUID: fileUUID1, fileGroupUUID: fileGroupUUID, sharingGroupUUID: sharingGroupUUID, userId: userId, deferredUploadId:deferredUploadId2, updateContents: comment2.updateContents, uploadCount: 1, uploadIndex: 1, state: .vNUploadFileChange) else {
            XCTFail()
            return
        }
        
        // Upload change for other file-- expecting this to *not* be pruned
        guard let deferredUpload3 = createDeferredUpload(sharingGroupUUID: sharingGroupUUID, status: .pendingChange),
            let deferredUploadId3 = deferredUpload3.deferredUploadId else {
            XCTFail()
            return
        }
            
        guard let upload3 = createUploadForTextFile(deviceUUID: deviceUUID, fileUUID: fileUUID2, sharingGroupUUID: sharingGroupUUID, userId: userId, deferredUploadId:deferredUploadId3, updateContents: comment3.updateContents, uploadCount: 1, uploadIndex: 1, state: .vNUploadFileChange) else {
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
        
        guard let fileIndex2 = getFileIndex(sharingGroupUUID: sharingGroupUUID, fileUUID: fileUUID2) else {
            XCTFail()
            return
        }
        
        // Expectation: File should be deleted.
        let found1 = try fileIsInCloudStorage(fileIndex: fileIndex1)
        XCTAssert(!found1)

        let found2 = try fileIsInCloudStorage(fileIndex: fileIndex2)
        XCTAssert(found2)
        
        XCTAssert(deferredCount == DeferredUploadRepository(db).count())
        XCTAssert(uploadCount == UploadRepository(db).count(), "\(uploadCount) != \(String(describing: UploadRepository(db).count())))")
    }
    
    func testRunTwoChangesAndThenOneDeletionForSameFilePlusOtherUploadChangeWithFileGroup() throws {
        try runTwoChangesAndThenOneDeletionForSameFilePlusOtherUploadChange(withFileGroup: true)
    }
    
    func testRunTwoChangesAndThenOneDeletionForSameFilePlusOtherUploadChangeWithoutFileGroup() throws {
        try runTwoChangesAndThenOneDeletionForSameFilePlusOtherUploadChange(withFileGroup: false)
    }
}
