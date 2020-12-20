
import XCTest
@testable import Server
@testable import TestsCommon
import LoggerAPI
import HeliumLogger
import Foundation
import ServerShared
import ChangeResolvers
import Credentials

class FileController_UploadDeletionTests: ServerTestCase, UploaderCommon {
    var accountManager: AccountManager!
    var services: Services!
    
    override func setUp() {
        super.setUp()

        accountManager = AccountManager()
        let credentials = Credentials()
        accountManager.setupAccounts(credentials: credentials)
        let resolverManager = ChangeResolverManager()

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
    
    func runDeletionOfOneFile(withFileGroup: Bool) throws {
        let deviceUUID = Foundation.UUID().uuidString
        let fileUUID = Foundation.UUID().uuidString
        
        var fileGroup: FileGroup?
        if withFileGroup {
            fileGroup = FileGroup(fileGroupUUID: Foundation.UUID().uuidString, objectType: "Foo")
        }
        
        guard let deferredCount = DeferredUploadRepository(db).count() else {
            XCTFail()
            return
        }
        
        guard let uploadCount = UploadRepository(db).count() else {
            XCTFail()
            return
        }

        // This file is going to be deleted.
        guard let uploadResult = uploadTextFile(uploadIndex: 1, uploadCount: 1, deviceUUID:deviceUUID, fileUUID: fileUUID, fileLabel: UUID().uuidString, fileGroup: fileGroup),
            let sharingGroupUUID = uploadResult.sharingGroupUUID else {
            XCTFail()
            return
        }

        let uploadDeletionRequest = UploadDeletionRequest()
        uploadDeletionRequest.sharingGroupUUID = sharingGroupUUID
        
        if let fileGroupUUID = fileGroup?.fileGroupUUID {
            uploadDeletionRequest.fileGroupUUID = fileGroupUUID
        }
        else {
            uploadDeletionRequest.fileUUID = fileUUID
        }
        
        guard let deletionResult = uploadDeletion(uploadDeletionRequest: uploadDeletionRequest, deviceUUID: deviceUUID, addUser: false) else {
            XCTFail()
            return
        }
        
        guard let deferredUploadId = deletionResult.deferredUploadId else {
            XCTFail()
            return
        }
        
        guard let fileIndex1 = getFileIndex(sharingGroupUUID: sharingGroupUUID, fileUUID: fileUUID) else {
            XCTFail()
            return
        }
        
        let found1 = try fileIsInCloudStorage(fileIndex: fileIndex1, services: services.uploaderServices)
        XCTAssert(!found1)
        
        guard let status = getUploadsResults(deviceUUID: deviceUUID, deferredUploadId: deferredUploadId) else {
            XCTFail()
            return
        }
        
        XCTAssert(status == .completed)
        
        XCTAssert(deferredCount + 1 == DeferredUploadRepository(db).count())
        XCTAssert(uploadCount == UploadRepository(db).count(), "\(uploadCount) != \(String(describing: UploadRepository(db).count())))")
    }
    
    func testDeletionOfOneFileWithNoFileGroup() throws {
        try runDeletionOfOneFile(withFileGroup: false)
    }
    
    func testDeletionOfOneFileWithFileGroup() throws {
        try runDeletionOfOneFile(withFileGroup: true)
    }
    
    func runTwoFileDeletions(withFileGroup: Bool) throws {
        let deviceUUID = Foundation.UUID().uuidString
        let fileUUID1 = Foundation.UUID().uuidString
        let fileUUID2 = Foundation.UUID().uuidString

        var fileGroup: FileGroup?
        if withFileGroup {
            fileGroup = FileGroup(fileGroupUUID: Foundation.UUID().uuidString, objectType: "Foo")
        }
        
        guard let deferredCount = DeferredUploadRepository(db).count() else {
            XCTFail()
            return
        }
        
        guard let uploadCount = UploadRepository(db).count() else {
            XCTFail()
            return
        }

        // These files are going to be deleted.
        guard let uploadResult = uploadTextFile(uploadIndex: 1, uploadCount: 1, deviceUUID:deviceUUID, fileUUID: fileUUID1, fileLabel: UUID().uuidString, fileGroup: fileGroup),
            let sharingGroupUUID = uploadResult.sharingGroupUUID else {
            XCTFail()
            return
        }
        
        guard let userId = uploadResult.uploadingUserId else {
            XCTFail()
            return
        }
        
        guard let _ = uploadTextFile(uploadIndex: 1, uploadCount: 1, deviceUUID:deviceUUID, fileUUID: fileUUID2, addUser: .no(sharingGroupUUID: sharingGroupUUID), fileLabel: UUID().uuidString, fileGroup: fileGroup) else {
            XCTFail()
            return
        }

        var deferredUploadId1: Int64?
        
        if fileGroup == nil {
            // Fake an earlier pending deletion, so that in this case we can actually run two non-file group deletions when the request is received.

            guard let deferredUpload = createDeferredUpload(userId: userId, sharingGroupUUID: sharingGroupUUID, status: .pendingDeletion),
                let deferredUploadId = deferredUpload.deferredUploadId else {
                XCTFail()
                return
            }
            
            deferredUploadId1 = deferredUpload.deferredUploadId
        
            guard let _ = createUploadForTextFile(deviceUUID: deviceUUID, fileUUID: fileUUID1, sharingGroupUUID: sharingGroupUUID, userId: userId, deferredUploadId: deferredUploadId, state: .deleteSingleFile) else {
                XCTFail()
                return
            }
        }
        
        let uploadDeletionRequest = UploadDeletionRequest()
        uploadDeletionRequest.sharingGroupUUID = sharingGroupUUID
        
        if let fileGroupUUID = fileGroup?.fileGroupUUID {
            uploadDeletionRequest.fileGroupUUID = fileGroupUUID
        }
        else {
            uploadDeletionRequest.fileUUID = fileUUID2
        }
        
        guard let uploadDeletionResult = uploadDeletion(uploadDeletionRequest: uploadDeletionRequest, deviceUUID: deviceUUID, addUser: false),
            let deferredUploadId2 = uploadDeletionResult.deferredUploadId else {
            XCTFail()
            return
        }

        if let deferredUploadId1 = deferredUploadId1 {
            guard let status1 = getUploadsResults(deviceUUID: deviceUUID, deferredUploadId: deferredUploadId1), status1 == .completed else {
                XCTFail()
                return
            }
        }
        
        guard let status2 = getUploadsResults(deviceUUID: deviceUUID, deferredUploadId: deferredUploadId2), status2 == .completed else {
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
        
        let found1 = try fileIsInCloudStorage(fileIndex: fileIndex1, services: services.uploaderServices)
        XCTAssert(!found1)
        let found2 = try fileIsInCloudStorage(fileIndex: fileIndex2, services: services.uploaderServices)
        XCTAssert(!found2)
        
        let extra: Int64 = (withFileGroup ? 1 : 2)
        XCTAssert(deferredCount + extra == DeferredUploadRepository(db).count(), "deferredCount - extra: \(deferredCount + extra) != DeferredUploadRepository(db).count(): \(String(describing: DeferredUploadRepository(db).count()))")
        
        XCTAssert(uploadCount == UploadRepository(db).count(), "\(uploadCount) != \(String(describing: UploadRepository(db).count())))")
    }
    
    func testTwoFileDeletionWithoutFileGroup() throws {
        try runTwoFileDeletions(withFileGroup: false)
    }
    
    func testTwoFileDeletionWithFileGroup() throws {
        try runTwoFileDeletions(withFileGroup: true)
    }
    
    func testMixedFileGroupAndNonFileGroupDeletion() throws {
        let deviceUUID = Foundation.UUID().uuidString
        let fileUUID1 = Foundation.UUID().uuidString
        let fileUUID2 = Foundation.UUID().uuidString
        let fileUUID3 = Foundation.UUID().uuidString
        
        let fileGroup = FileGroup(fileGroupUUID: Foundation.UUID().uuidString, objectType: "Foo")
        
        guard let deferredCount = DeferredUploadRepository(db).count() else {
            XCTFail()
            return
        }
        
        guard let uploadCount = UploadRepository(db).count() else {
            XCTFail()
            return
        }

        // These files are going to be deleted.
        guard let uploadResult = uploadTextFile(uploadIndex: 1, uploadCount: 1, deviceUUID:deviceUUID, fileUUID: fileUUID1, fileLabel: UUID().uuidString, fileGroup: fileGroup),
            let sharingGroupUUID = uploadResult.sharingGroupUUID else {
            XCTFail()
            return
        }
        
        guard let userId = uploadResult.uploadingUserId else {
            XCTFail()
            return
        }
        
        guard let _ = uploadTextFile(uploadIndex: 1, uploadCount: 1, deviceUUID:deviceUUID, fileUUID: fileUUID2, addUser: .no(sharingGroupUUID: sharingGroupUUID), fileLabel: UUID().uuidString, fileGroup: fileGroup) else {
            XCTFail()
            return
        }
        
        guard let _ = uploadTextFile(uploadIndex: 1, uploadCount: 1, deviceUUID:deviceUUID, fileUUID: fileUUID3, addUser: .no(sharingGroupUUID: sharingGroupUUID), fileLabel: UUID().uuidString, fileGroup: nil) else {
            XCTFail()
            return
        }
        
        // Fake pending deletion for a non-file group.
        guard let deferredUpload = createDeferredUpload(userId: userId, sharingGroupUUID: sharingGroupUUID, status: .pendingDeletion),
            let deferredUploadId1 = deferredUpload.deferredUploadId else {
            XCTFail()
            return
        }
    
        guard let _ = createUploadForTextFile(deviceUUID: deviceUUID, fileUUID: fileUUID3, sharingGroupUUID: sharingGroupUUID, userId: userId, deferredUploadId: deferredUploadId1, state: .deleteSingleFile) else {
            XCTFail()
            return
        }

        let uploadDeletionRequest = UploadDeletionRequest()
        uploadDeletionRequest.sharingGroupUUID = sharingGroupUUID
        uploadDeletionRequest.fileGroupUUID = fileGroup.fileGroupUUID

        guard let deletionResult = uploadDeletion(uploadDeletionRequest: uploadDeletionRequest, deviceUUID: deviceUUID, addUser: false),
            let deferredUploadId2 = deletionResult.deferredUploadId else {
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

        guard let fileIndex3 = getFileIndex(sharingGroupUUID: sharingGroupUUID, fileUUID: fileUUID3) else {
            XCTFail()
            return
        }
        
        guard let status1 = getUploadsResults(deviceUUID: deviceUUID, deferredUploadId: deferredUploadId1), status1 == .completed else {
            XCTFail()
            return
        }
        
        guard let status2 = getUploadsResults(deviceUUID: deviceUUID, deferredUploadId: deferredUploadId2), status2 == .completed else {
            XCTFail()
            return
        }
        
        let found1 = try fileIsInCloudStorage(fileIndex: fileIndex1, services: services.uploaderServices)
        XCTAssert(!found1)
        let found2 = try fileIsInCloudStorage(fileIndex: fileIndex2, services: services.uploaderServices)
        XCTAssert(!found2)
        let found3 = try fileIsInCloudStorage(fileIndex: fileIndex3, services: services.uploaderServices)
        XCTAssert(!found3)
        
        XCTAssert(deferredCount + 2 == DeferredUploadRepository(db).count())
        XCTAssert(uploadCount == UploadRepository(db).count(), "\(uploadCount) != \(String(describing: UploadRepository(db).count())))")
    }
    
    enum FileGroupDeletion {
        case deleteFileHavingFileGroupWithFileUUIDFails
        case deleteFileHavingFileGroupWithFileGroupWorks
    }
    
    func runUploadDeletion(withTest: FileGroupDeletion) throws {
        let deviceUUID = Foundation.UUID().uuidString
        let fileUUID = Foundation.UUID().uuidString
        let fileGroup = FileGroup(fileGroupUUID: Foundation.UUID().uuidString, objectType: "Foo")

        guard let uploadResult = uploadTextFile(uploadIndex: 1, uploadCount: 1, deviceUUID:deviceUUID, fileUUID: fileUUID, fileLabel: UUID().uuidString, fileGroup: fileGroup),
            let sharingGroupUUID = uploadResult.sharingGroupUUID else {
            XCTFail()
            return
        }
        
        var expectError: Bool = false
        
        let uploadDeletionRequest = UploadDeletionRequest()
        uploadDeletionRequest.sharingGroupUUID = sharingGroupUUID
        
        switch withTest {
        case .deleteFileHavingFileGroupWithFileUUIDFails:
            uploadDeletionRequest.fileUUID = fileUUID
            expectError = true
            
        case .deleteFileHavingFileGroupWithFileGroupWorks:
            uploadDeletionRequest.fileGroupUUID = fileGroup.fileGroupUUID
        }
        
        let deletionResult = uploadDeletion(uploadDeletionRequest: uploadDeletionRequest, deviceUUID: deviceUUID, addUser: false, expectError: expectError, expectingUploaderToRun: !expectError)

        switch withTest {
        case .deleteFileHavingFileGroupWithFileUUIDFails:
            XCTAssert(deletionResult == nil)
        case .deleteFileHavingFileGroupWithFileGroupWorks:
            guard let deletionResult = deletionResult,
                let deferredUploadId = deletionResult.deferredUploadId else {
                XCTFail()
                return
            }
            
            guard let status = getUploadsResults(deviceUUID: deviceUUID, deferredUploadId: deferredUploadId), status == .completed else {
                XCTFail()
                return
            }
        }
    }
    
    func testUploadDeletionWithFileUUIDWithFileGroupFileFails() throws {
        try runUploadDeletion(withTest: .deleteFileHavingFileGroupWithFileUUIDFails)
    }
    
    func testUploadDeletionWithFileGroupWithFileGroupFileWorks() throws {
        try runUploadDeletion(withTest: .deleteFileHavingFileGroupWithFileGroupWorks)
    }
    
    func testThatUploadDeletionTwiceOfSameFileWorks() throws {
        let deviceUUID = Foundation.UUID().uuidString
        let fileUUID = Foundation.UUID().uuidString
        
        guard let deferredCount = DeferredUploadRepository(db).count() else {
            XCTFail()
            return
        }
        
        guard let uploadCount = UploadRepository(db).count() else {
            XCTFail()
            return
        }

        // This file is going to be deleted.
        guard let uploadResult = uploadTextFile(uploadIndex: 1, uploadCount: 1, deviceUUID:deviceUUID, fileUUID: fileUUID, fileLabel: UUID().uuidString),
            let sharingGroupUUID = uploadResult.sharingGroupUUID else {
            XCTFail()
            return
        }

        let uploadDeletionRequest = UploadDeletionRequest()
        uploadDeletionRequest.sharingGroupUUID = sharingGroupUUID
        uploadDeletionRequest.fileUUID = fileUUID
        
        guard let deletionResult1 = uploadDeletion(uploadDeletionRequest: uploadDeletionRequest, deviceUUID: deviceUUID, addUser: false),
            let deferredUploadId = deletionResult1.deferredUploadId else {
            XCTFail()
            return
        }
        
        guard let _ = uploadDeletion(uploadDeletionRequest: uploadDeletionRequest, deviceUUID: deviceUUID, addUser: false, expectingUploaderToRun: false) else {
            XCTFail()
            return
        }
        
        guard let fileIndex = getFileIndex(sharingGroupUUID: sharingGroupUUID, fileUUID: fileUUID) else {
            XCTFail()
            return
        }
        
        let found1 = try fileIsInCloudStorage(fileIndex: fileIndex, services: services.uploaderServices)
        XCTAssert(!found1)
        
        guard let status = getUploadsResults(deviceUUID: deviceUUID, deferredUploadId: deferredUploadId), status == .completed else {
            XCTFail()
            return
        }
        
        XCTAssert(deferredCount + 1 == DeferredUploadRepository(db).count())
        XCTAssert(uploadCount == UploadRepository(db).count(), "\(uploadCount) != \(String(describing: UploadRepository(db).count())))")
    }
    
    // What about one pending deletion for a file, and an actual upload deletion. Simulating a deletion that hasn't been processed yet (e.g., by another client), and a further deletion.
    // Hmmm. On thinking about it more, I'm not sure this can actually happen. The first client to mark the file as deleted in the FileIndex will stop any other clients from successfully creating a second deletion.
    func testDeletionByOneClientAndAnotherDeletionByOtherClientWorks() {
        let deviceUUID1 = Foundation.UUID().uuidString
        let deviceUUID2 = Foundation.UUID().uuidString
        let fileUUID = Foundation.UUID().uuidString

        let account = TestAccount.dropbox1
        guard let uploadResult = uploadTextFile(uploadIndex: 1, uploadCount: 1, testAccount: account, deviceUUID:deviceUUID1, fileUUID: fileUUID, fileLabel: UUID().uuidString),
            let sharingGroupUUID = uploadResult.sharingGroupUUID else {
            XCTFail()
            return
        }
        guard let userId = uploadResult.uploadingUserId else {
            XCTFail()
            return
        }
        
        guard let deferredUpload = createDeferredUpload(userId: userId, sharingGroupUUID: sharingGroupUUID, status: .pendingDeletion),
            let deferredUploadId1 = deferredUpload.deferredUploadId else {
            XCTFail()
            return
        }
    
        guard let _ = createUploadForTextFile(deviceUUID: deviceUUID2, fileUUID: fileUUID, sharingGroupUUID: sharingGroupUUID, userId: userId, deferredUploadId: deferredUploadId1, state: .deleteSingleFile) else {
            XCTFail()
            return
        }
        
        let uploadDeletionRequest = UploadDeletionRequest()
        uploadDeletionRequest.sharingGroupUUID = sharingGroupUUID
        uploadDeletionRequest.fileUUID = fileUUID
        
        guard let deletionResult = uploadDeletion(testAccount: account, uploadDeletionRequest: uploadDeletionRequest, deviceUUID: deviceUUID2, addUser: false),
            let deferredUploadId2 = deletionResult.deferredUploadId else {
            XCTFail()
            return
        }
        
        guard let status1 = getUploadsResults(testAccount: account, deviceUUID: deviceUUID1, deferredUploadId: deferredUploadId1),
            status1 == .completed else {
            XCTFail()
            return
        }
        
        guard let status2 = getUploadsResults(testAccount: account, deviceUUID: deviceUUID1, deferredUploadId: deferredUploadId2),
            status2 == .completed else {
            XCTFail()
            return
        }
    }
    
    func testThatDeletionOfUnknownFileUUIDFails() {
        let deviceUUID = Foundation.UUID().uuidString
        let fileUUID = Foundation.UUID().uuidString

        // Using this upload file only for creating a user.
        guard let uploadResult = uploadTextFile(uploadIndex: 1, uploadCount: 1, deviceUUID:deviceUUID, fileUUID: fileUUID, fileLabel: UUID().uuidString),
            let sharingGroupUUID = uploadResult.sharingGroupUUID else {
            XCTFail()
            return
        }

        let uploadDeletionRequest = UploadDeletionRequest()
        uploadDeletionRequest.sharingGroupUUID = sharingGroupUUID
        
        let unknownFileUUID = Foundation.UUID().uuidString
        uploadDeletionRequest.fileUUID = unknownFileUUID
        
        let deletionResult = uploadDeletion(uploadDeletionRequest: uploadDeletionRequest, deviceUUID: deviceUUID, addUser: false, expectError: true, expectingUploaderToRun: false)
        XCTAssert(deletionResult == nil)
    }
    
    func testThatUploadByOneDeviceAndDeletionByAnotherActuallyDeletes() throws {
        let deviceUUID1 = Foundation.UUID().uuidString
        let deviceUUID2 = Foundation.UUID().uuidString
        let fileUUID = Foundation.UUID().uuidString

        // Using this upload file only for creating a user.
        guard let uploadResult = uploadTextFile(uploadIndex: 1, uploadCount: 1, deviceUUID:deviceUUID1, fileUUID: fileUUID, fileLabel: UUID().uuidString),
            let sharingGroupUUID = uploadResult.sharingGroupUUID else {
            XCTFail()
            return
        }

        let uploadDeletionRequest = UploadDeletionRequest()
        uploadDeletionRequest.sharingGroupUUID = sharingGroupUUID
        uploadDeletionRequest.fileUUID = fileUUID
        
        guard let deletionResult = uploadDeletion(uploadDeletionRequest: uploadDeletionRequest, deviceUUID: deviceUUID2, addUser: false),
            let deferredUploadId = deletionResult.deferredUploadId else {
            XCTFail()
            return
        }
        
        guard let fileIndex = getFileIndex(sharingGroupUUID: sharingGroupUUID, fileUUID: fileUUID) else {
            XCTFail()
            return
        }
        
        let found1 = try fileIsInCloudStorage(fileIndex: fileIndex, services: services.uploaderServices)
        XCTAssert(!found1)
        
        guard let status = getUploadsResults(deviceUUID: deviceUUID1, deferredUploadId: deferredUploadId),
            status == .completed else {
            XCTFail()
            return
        }
    }
    
    func testThatUploadDeletionWithUnknownSharingGroupUUIDFails() {
        let deviceUUID = Foundation.UUID().uuidString
        let fileUUID = Foundation.UUID().uuidString

        // Using this upload file only for creating a user.
        guard let _ = uploadTextFile(uploadIndex: 1, uploadCount: 1, deviceUUID:deviceUUID, fileUUID: fileUUID, fileLabel: UUID().uuidString) else {
            XCTFail()
            return
        }

        let uploadDeletionRequest = UploadDeletionRequest()
        let unknownSharingGroupUUID = Foundation.UUID().uuidString
        uploadDeletionRequest.sharingGroupUUID = unknownSharingGroupUUID
        uploadDeletionRequest.fileUUID = fileUUID
        
        let deletionResult = uploadDeletion(uploadDeletionRequest: uploadDeletionRequest, deviceUUID: deviceUUID, addUser: false, expectError: true, expectingUploaderToRun: false)
        XCTAssert(deletionResult == nil)
    }
    
    func testUploadDeletionOfVNFileWorks() {
        let changeResolverName = CommentFile.changeResolverName
        let deviceUUID = Foundation.UUID().uuidString
        let fileUUID = Foundation.UUID().uuidString
        
        let exampleComment = ExampleComment(messageString: "Hello, World", id: Foundation.UUID().uuidString)
         
        // First upload the v0 file.
  
        guard let result = uploadTextFile(uploadIndex: 1, uploadCount: 1, mimeType: TestFile.commentFile.mimeType, deviceUUID:deviceUUID, fileUUID: fileUUID, fileLabel: UUID().uuidString, stringFile: .commentFile, changeResolverName: changeResolverName),
            let sharingGroupUUID = result.sharingGroupUUID else {
            XCTFail()
            return
        }
                
        // Next, upload v1 of the file -- i.e., upload just the specific change to the file.
        
        guard let _ = uploadTextFile(uploadIndex: 1, uploadCount: 1, testAccount: .primaryOwningAccount, mimeType: nil, deviceUUID: deviceUUID, fileUUID: fileUUID, addUser: .no(sharingGroupUUID: sharingGroupUUID), fileLabel: nil, dataToUpload: exampleComment.updateContents) else {
            XCTFail()
            return
        }
        
        let uploadDeletionRequest = UploadDeletionRequest()
        uploadDeletionRequest.sharingGroupUUID = sharingGroupUUID
        uploadDeletionRequest.fileUUID = fileUUID
        
        guard let uploadResult = uploadDeletion(uploadDeletionRequest: uploadDeletionRequest, deviceUUID: deviceUUID, addUser: false),
            let deferredUploadId = uploadResult.deferredUploadId else {
            XCTFail()
            return
        }
        
        guard let status = getUploadsResults(deviceUUID: deviceUUID, deferredUploadId: deferredUploadId),
            status == .completed else {
            XCTFail()
            return
        }
    }
}
