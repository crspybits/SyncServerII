//
//  Sharing_FileManipulationTests.swift
//  Server
//
//  Created by Christopher Prince on 4/15/17.
//
//

import XCTest
@testable import Server
@testable import TestsCommon
import LoggerAPI
import Foundation
import ServerShared
import Kitura
import ServerAccount
import ChangeResolvers
import Credentials

// Needs: .primarySharingAccount, .nonOwningSharingAccount, .secondarySharingAccount, .secondaryOwningAccount

class Sharing_FileManipulationTests: ServerTestCase {
    var accountManager: AccountManager!
    
    override func setUp() {
        super.setUp()
        accountManager = AccountManager()
        accountManager.setupAccounts(credentials: Credentials())
    }
    
    override func tearDown() {
        super.tearDown()
    }

    struct SharingUploadResult {
        let request: UploadFileRequest
        let response: UploadFileResponse
        let checkSum:String?
        let sharingTestAccount:TestAccount
        let uploadedDeviceUUID: String
        let redeemResponse: RedeemSharingInvitationResponse
    }
    
    // If not adding a user, you must pass a sharingGroupUUID.
    @discardableResult
    func uploadFileBySharingUser(withPermission sharingPermission:Permission, owningAccount: TestAccount, sharingUser: TestAccount = .primarySharingAccount, addUser: Bool = true, sharingGroupUUID: String, failureExpected:Bool = false, fileUUID:String? = nil, mimeType: MimeType?, file: TestFile?, dataToUpload: Data? = nil, v0File:Bool = true) -> SharingUploadResult? {
        let deviceUUID1 = Foundation.UUID().uuidString
        
        if addUser {
            guard let _ = addNewUser(testAccount: owningAccount, sharingGroupUUID: sharingGroupUUID, deviceUUID:deviceUUID1) else {
                XCTFail()
                return nil
            }
        }
                
        // Have that newly created user create a sharing invitation.
        guard let sharingInvitationUUID = createSharingInvitation(testAccount: owningAccount, permission: sharingPermission, sharingGroupUUID:sharingGroupUUID) else {
            XCTFail()
            return nil
        }
                
        // Redeem that sharing invitation with a new user
        guard let redeemResponse = redeemSharingInvitation(sharingUser: sharingUser, sharingInvitationUUID:sharingInvitationUUID) else {
            XCTFail()
            return nil
        }
        
        let deviceUUID2 = Foundation.UUID().uuidString
        
        var owningAccountType: AccountScheme.AccountName
        var fileLabel: String?

        if v0File {
            fileLabel = UUID().uuidString
            switch sharingUser.scheme.userType {
            case .owning:
                owningAccountType = sharingUser.scheme.accountName
            case .sharing:
                owningAccountType = owningAccount.scheme.accountName
            }
        }
        else {
            owningAccountType = owningAccount.scheme.accountName
        }
        
        // Attempting to upload a file by our sharing user        
        guard let uploadResult = uploadTextFile(testAccount: sharingUser, mimeType: mimeType, owningAccountType: owningAccountType, deviceUUID:deviceUUID2, fileUUID: fileUUID, addUser: .no(sharingGroupUUID:sharingGroupUUID), fileLabel: fileLabel, errorExpected: failureExpected, stringFile: file, dataToUpload: dataToUpload) else {
            if !failureExpected {
                XCTFail()
            }
            return nil
        }
        
        guard let response = uploadResult.response else {
            XCTFail()
            return nil
        }
        
        return SharingUploadResult(request: uploadResult.request, response: response, checkSum: uploadResult.checkSum, sharingTestAccount: sharingUser, uploadedDeviceUUID:deviceUUID2, redeemResponse: redeemResponse)
    }
    
    func uploadDeleteFileBySharingUser(withPermission sharingPermission:Permission, sharingUser: TestAccount = .primarySharingAccount, failureExpected:Bool = false) {
        let deviceUUID1 = Foundation.UUID().uuidString
        let sharingGroupUUID = Foundation.UUID().uuidString

        guard let _ = addNewUser(testAccount: .primaryOwningAccount, sharingGroupUUID: sharingGroupUUID, deviceUUID:deviceUUID1) else {
            XCTFail()
            return
        }
        
        // And upload a file by that user.
        guard let uploadResult = uploadTextFile(testAccount: .primaryOwningAccount, deviceUUID:deviceUUID1, addUser:.no(sharingGroupUUID: sharingGroupUUID), fileLabel: UUID().uuidString) else {
            XCTFail()
            return
        }
                
        // Have that newly created user create a sharing invitation.
        guard let sharingInvitationUUID = createSharingInvitation(permission: sharingPermission, sharingGroupUUID:sharingGroupUUID) else {
            XCTFail()
            return
        }

        // Redeem that sharing invitation with a new user
        guard let _ = redeemSharingInvitation(sharingUser: sharingUser, sharingInvitationUUID:sharingInvitationUUID) else {
            XCTFail()
            return
        }
        
        let deviceUUID2 = Foundation.UUID().uuidString

        let uploadDeletionRequest = UploadDeletionRequest()
        uploadDeletionRequest.fileUUID = uploadResult.request.fileUUID
        uploadDeletionRequest.sharingGroupUUID = sharingGroupUUID
        
        let deletionResponse = uploadDeletion(testAccount: sharingUser, uploadDeletionRequest: uploadDeletionRequest, deviceUUID: deviceUUID2, addUser: false, expectError: failureExpected, expectingUploaderToRun: !failureExpected)
        if failureExpected {
            XCTAssert(deletionResponse == nil)
        }
        else {
            XCTAssert(deletionResponse != nil)
        }
    }
    
    func downloadFileBySharingUser(withPermission sharingPermission:Permission, sharingUser: TestAccount = .primarySharingAccount, failureExpected:Bool = false) {
        let deviceUUID1 = Foundation.UUID().uuidString
        let sharingGroupUUID = Foundation.UUID().uuidString

        guard let _ = addNewUser(testAccount: .primaryOwningAccount, sharingGroupUUID: sharingGroupUUID, deviceUUID:deviceUUID1) else {
            XCTFail()
            return
        }
        
        // And upload a file by that user.
        guard let uploadResult = uploadTextFile(testAccount: .primaryOwningAccount, deviceUUID:deviceUUID1, addUser:.no(sharingGroupUUID: sharingGroupUUID), fileLabel: UUID().uuidString) else {
            XCTFail()
            return
        }
        
        // Have that newly created user create a sharing invitation.
        guard let sharingInvitationUUID = createSharingInvitation(permission: sharingPermission, sharingGroupUUID:sharingGroupUUID) else {
            XCTFail()
            return
        }
        
        guard let _ = redeemSharingInvitation(sharingUser: sharingUser, sharingInvitationUUID:sharingInvitationUUID) else {
            XCTFail()
            return
        }
        
        guard let fileUUID = uploadResult.request.fileUUID else {
            XCTFail()
            return
        }
        
        // Now see if we can download the file with the sharing user creds.
        guard let _ = downloadFile(testAccount: sharingUser, fileUUID: fileUUID, fileVersion: 0, sharingGroupUUID: sharingGroupUUID, deviceUUID: deviceUUID1) else {
            XCTFail()
            return
        }
    }
    
    func downloadDeleteFileBySharingUser(withPermission sharingPermission:Permission, sharingUser: TestAccount = .primarySharingAccount, failureExpected:Bool = false) {
    
        let deviceUUID1 = Foundation.UUID().uuidString
        let sharingGroupUUID = Foundation.UUID().uuidString

        guard let _ = addNewUser(testAccount: .primaryOwningAccount, sharingGroupUUID: sharingGroupUUID, deviceUUID:deviceUUID1) else {
            XCTFail()
            return
        }
        
        // And upload a file by that user.
        guard let uploadResult = uploadTextFile(testAccount: .primaryOwningAccount, deviceUUID:deviceUUID1, addUser:.no(sharingGroupUUID: sharingGroupUUID), fileLabel: UUID().uuidString) else {
            XCTFail()
            return
        }
        
        let uploadDeletionRequest = UploadDeletionRequest()
        uploadDeletionRequest.fileUUID = uploadResult.request.fileUUID
        uploadDeletionRequest.sharingGroupUUID = sharingGroupUUID
        
        guard let _ = uploadDeletion(uploadDeletionRequest: uploadDeletionRequest, deviceUUID: deviceUUID1, addUser: false, expectError: failureExpected) else {
            XCTFail()
            return
        }
                
        // Have that newly created user create a sharing invitation.
        guard let sharingInvitationUUID = createSharingInvitation(permission: sharingPermission, sharingGroupUUID:sharingGroupUUID) else {
            XCTFail()
            return
        }
        
        // Redeem that sharing invitation with a new user
        guard let _ = redeemSharingInvitation(sharingUser: sharingUser, sharingInvitationUUID:sharingInvitationUUID) else {
            XCTFail()
            return
        }
    
        // The final step of a download deletion is to check the file index-- and make sure it's marked as deleted for us.
        
        let deviceUUID2 = Foundation.UUID().uuidString
        
        guard let (files, _) = getIndex(testAccount: sharingUser, deviceUUID:deviceUUID2, sharingGroupUUID: sharingGroupUUID),
            let fileIndex = files, fileIndex.count == 1 else {
            XCTFail()
            return
        }
        
        XCTAssert(fileIndex[0].deleted == true)
    }

    // MARK: Read sharing user
    func testThatReadSharingUserCannotUploadAFile() {
        let sharingGroupUUID = UUID().uuidString
        let result = uploadFileBySharingUser(withPermission: .read, owningAccount: .primaryOwningAccount, sharingGroupUUID: sharingGroupUUID, failureExpected:true, mimeType: TestFile.test1.mimeType, file: .test1)
        XCTAssert(result == nil)
    }
    
    func testThatReadSharingUserCannotUploadDeleteAFile() {
        uploadDeleteFileBySharingUser(withPermission: .read, failureExpected:true)
    }
    
    func testThatReadSharingUserCanDownloadAFile() {
        downloadFileBySharingUser(withPermission: .read)
    }
       
    func testThatReadSharingUserCanDownloadDeleteAFile() {
        downloadDeleteFileBySharingUser(withPermission: .read)
    }
    
    func checkFileOwner(uploadedDeviceUUID: String, owningAccount: TestAccount, ownerUserId: UserId, request: UploadFileRequest, mimeType: String, fileVersion: FileVersionInt = 0) -> Bool {
        
        let options = CloudStorageFileNameOptions(cloudFolderName: ServerTestCase.cloudFolderName, mimeType: mimeType)
        
        guard let fileUUID = request.fileUUID else {
            XCTFail()
            return false
        }
        
        let fileName = Filename.inCloud(deviceUUID: uploadedDeviceUUID, fileUUID: fileUUID, mimeType: mimeType, fileVersion: fileVersion)
        
        Log.debug("Looking for file: \(fileName)")
        guard let found = lookupFile(forOwningTestAccount: owningAccount, cloudFileName: fileName, options: options), found else {
            XCTFail()
            return false
        }
        
        var fileIndexObj: FileInfo!
        
        let fileIndexResult = FileIndexRepository(db).fileIndex(forSharingGroupUUID: request.sharingGroupUUID)
        switch fileIndexResult {
        case .fileIndex(let fileIndex):
            guard fileIndex.count > 0 else {
                XCTFail("fileIndex.count: \(fileIndex.count)")
                return false
            }
            
            let filtered = fileIndex.filter {$0.fileUUID == request.fileUUID}
            guard filtered.count == 1 else {
                XCTFail()
                return false
            }
            
            fileIndexObj = filtered[0]
            
        case .error(_):
            XCTFail()
            return false
        }
        
        guard fileIndexObj.cloudStorageType != nil else {
            XCTFail()
            return false
        }
        
        // Need to make sure that the cloud storage type of the file, in the file index, corresponds to the cloud storage type of the owningAccount.
        guard owningAccount.scheme.cloudStorageType == fileIndexObj.cloudStorageType else {
            XCTFail()
            return false
        }
        
        return true
    }

    // Check to make sure that if the invited user owns cloud storage that the file was uploaded to their cloud storage.
    func makeSureSharingOwnerOwnsUploadedFile(result: SharingUploadResult, mimeType: String) -> Bool {
        if result.sharingTestAccount.scheme.userType == .owning {
            return checkFileOwner(uploadedDeviceUUID: result.uploadedDeviceUUID, owningAccount: result.sharingTestAccount, ownerUserId: result.redeemResponse.userId, request: result.request, mimeType: mimeType)
        }
        return false
    }
    
    // MARK: Write sharing user
    
    func testThatWriteSharingUserCanUploadAFile() {
        let sharingGroupUUID = UUID().uuidString
        let mimeType = TestFile.test1.mimeType
        
        guard let result = uploadFileBySharingUser(withPermission: .write, owningAccount: .primaryOwningAccount, sharingGroupUUID: sharingGroupUUID, mimeType: mimeType, file: .test1) else {
            XCTFail()
            return
        }
        
        XCTAssert(makeSureSharingOwnerOwnsUploadedFile(result: result, mimeType: mimeType.rawValue))
    }
    
    // When an owning user uploads a modified file (v1) which was initially uploaded (v0) by another owning user, that original owning user must remain the owner of the modified file.
    func testThatV0FileOwnerRemainsFileOwner() {
        let file: TestFile = .commentFile
        let changeResolverName = CommentFile.changeResolverName
        let owningAccount:TestAccount = .primaryOwningAccount
        let deviceUUID = Foundation.UUID().uuidString
        let comment = ExampleComment(messageString: "Example", id: Foundation.UUID().uuidString)

        // Upload v0 of file.
        guard let uploadResult = uploadTextFile(testAccount: owningAccount, deviceUUID:deviceUUID, fileLabel: UUID().uuidString, stringFile: file, changeResolverName: changeResolverName),
            let sharingGroupUUID = uploadResult.sharingGroupUUID,
            let v0UserId = uploadResult.uploadingUserId else {
            XCTFail()
            return
        }
        
        // Upload v1 of file by another (sharing) user
        guard let uploadResult2 = uploadFileBySharingUser(withPermission: .write, owningAccount: owningAccount, sharingUser: .primarySharingAccount, addUser: false, sharingGroupUUID: sharingGroupUUID, fileUUID: uploadResult.request.fileUUID, mimeType: nil, file: nil, dataToUpload: comment.updateContents, v0File: false) else {
            XCTFail()
            return
        }
        
        guard let deferredUploadId = uploadResult2.response.deferredUploadId else {
            XCTFail()
            return
        }
        
        // Get uploads results by .primarySharingAccount because that was the account that uploaded the v1 change.
        guard let status = getUploadsResults(testAccount: .primarySharingAccount, deviceUUID: deviceUUID, deferredUploadId: deferredUploadId), status == .completed else {
            XCTFail()
            return
        }
        
        // Check that the v0 owner still owns the v1 file.
        XCTAssert(checkFileOwner(uploadedDeviceUUID: deviceUUID, owningAccount: owningAccount, ownerUserId: v0UserId, request: uploadResult2.request, mimeType: file.mimeType.rawValue, fileVersion: 1))
    }
    
    func testThatWriteSharingUserCanUploadDeleteAFile() {
        uploadDeleteFileBySharingUser(withPermission: .write)
    }
    
    // Upload deletion with files with v0 owners that are different.
    func testUploadDeletionWithDifferentV0OwnersWorks() {
        // Upload v0 of file by .primaryOwningAccount user
        let deviceUUID = Foundation.UUID().uuidString
        guard let upload1 = uploadTextFile(deviceUUID:deviceUUID, fileLabel: UUID().uuidString),
            let sharingGroupUUID = upload1.sharingGroupUUID else {
            XCTFail()
            return
        }
        
        let file: TestFile = .test1
        let mimeType = file.mimeType
        
        guard let upload2 = uploadFileBySharingUser(withPermission: .write, owningAccount: .primaryOwningAccount, addUser: false, sharingGroupUUID: sharingGroupUUID, mimeType: mimeType, file: file) else {
            XCTFail()
            return
        }
        
        let uploadDeletionRequest1 = UploadDeletionRequest()
        uploadDeletionRequest1.fileUUID = upload1.request.fileUUID
        uploadDeletionRequest1.sharingGroupUUID = sharingGroupUUID

        guard let deletionResult1 = uploadDeletion(testAccount: upload2.sharingTestAccount, uploadDeletionRequest: uploadDeletionRequest1, deviceUUID: deviceUUID, addUser: false),
            let deferredUploadId1 = deletionResult1.deferredUploadId else {
            XCTFail()
            return
        }
        
        guard let status1 = getUploadsResults(testAccount: upload2.sharingTestAccount, deviceUUID: deviceUUID, deferredUploadId: deferredUploadId1), status1 == .completed else {
            XCTFail()
            return
        }

        let uploadDeletionRequest2 = UploadDeletionRequest()
        uploadDeletionRequest2.fileUUID = upload2.request.fileUUID
        uploadDeletionRequest2.sharingGroupUUID = sharingGroupUUID

        guard let deletionResult2 = uploadDeletion(testAccount: upload2.sharingTestAccount, uploadDeletionRequest: uploadDeletionRequest2, deviceUUID: deviceUUID, addUser: false),
            let deferredUploadId2 = deletionResult2.deferredUploadId else {
            XCTFail()
            return
        }
        
        guard let status2 = getUploadsResults(testAccount: upload2.sharingTestAccount, deviceUUID: deviceUUID, deferredUploadId: deferredUploadId2), status2 == .completed else {
            XCTFail()
            return
        }
    }

    // Upload deletions must go to the account of the original (v0) owning user. To test this: a) upload v0 of a file, b) have a different user upload v1 of the file. Now upload delete. Make sure the deletion works.
    func testThatUploadDeletionOfFileAfterV1UploadBySharingUserWorks() {
        // Upload v0 of file.
        let deviceUUID = Foundation.UUID().uuidString
        let file: TestFile = .commentFile
        let mimeType: MimeType = file.mimeType
        let comment = ExampleComment(messageString: "Example", id: Foundation.UUID().uuidString)
        let changeResolverName = CommentFile.changeResolverName

        guard let uploadResult = uploadTextFile(mimeType: mimeType, deviceUUID:deviceUUID, fileLabel: UUID().uuidString, stringFile: file, changeResolverName: changeResolverName),
            let sharingGroupUUID = uploadResult.sharingGroupUUID else {
            XCTFail()
            return
        }
                
        // upload v1 of file
        guard let _ = uploadFileBySharingUser(withPermission: .write, owningAccount: .primaryOwningAccount, addUser: false, sharingGroupUUID: sharingGroupUUID, fileUUID: uploadResult.request.fileUUID, mimeType: nil, file: nil, dataToUpload: comment.updateContents, v0File: false) else {
            XCTFail()
            return
        }
                
        let uploadDeletionRequest = UploadDeletionRequest()
        uploadDeletionRequest.fileUUID = uploadResult.request.fileUUID
        uploadDeletionRequest.sharingGroupUUID = sharingGroupUUID
        
        // Original v0 uploader deletes file.
        guard let deletionResult = uploadDeletion(testAccount: .primaryOwningAccount, uploadDeletionRequest: uploadDeletionRequest, deviceUUID: deviceUUID, addUser: false) else {
            XCTFail()
            return
        }
        
        guard let deferredUploadId = deletionResult.deferredUploadId else {
            XCTFail()
            return
        }
        
        guard let status = getUploadsResults(testAccount: .primaryOwningAccount, deviceUUID: deviceUUID, deferredUploadId: deferredUploadId), status == .completed else {
            XCTFail()
            return
        }
    }

    // Make sure file actually gets deleted in cloud storage for non-root owning users.
    func testUploadDeletionForNonRootOwningUserWorks() {
        let sharingGroupUUID = UUID().uuidString
        let file: TestFile = .commentFile
        let mimeType: MimeType = file.mimeType
        
        guard let result = uploadFileBySharingUser(withPermission: .write, owningAccount: .primaryOwningAccount, sharingGroupUUID: sharingGroupUUID, mimeType: mimeType, file: file) else {
            XCTFail()
            return
        }
                
        let uploadDeletionRequest = UploadDeletionRequest()
        uploadDeletionRequest.fileUUID = result.request.fileUUID
        uploadDeletionRequest.sharingGroupUUID = sharingGroupUUID
        
        // Original v0 uploader deletes file.
        guard let deletionResult = uploadDeletion(testAccount: result.sharingTestAccount, uploadDeletionRequest: uploadDeletionRequest, deviceUUID: result.uploadedDeviceUUID, addUser: false) else {
            XCTFail()
            return
        }
        
        guard let deferredUploadId = deletionResult.deferredUploadId else {
            XCTFail()
            return
        }
        
        guard let status = getUploadsResults(testAccount: result.sharingTestAccount, deviceUUID: result.uploadedDeviceUUID, deferredUploadId: deferredUploadId), status == .completed else {
            XCTFail()
            return
        }

        let options = CloudStorageFileNameOptions(cloudFolderName: ServerTestCase.cloudFolderName, mimeType: mimeType.rawValue)
        
        // The owner of the file will be either (a) the sharing user if that user is an owning user, or (b) the inviting user otherwise.
        
        var owningUser: TestAccount!
        if result.sharingTestAccount.scheme.userType == .owning {
            owningUser = result.sharingTestAccount
        }
        else {
            owningUser = .primaryOwningAccount
        }

        let fileName = Filename.inCloud(deviceUUID: result.uploadedDeviceUUID, fileUUID: result.request.fileUUID, mimeType: mimeType.rawValue, fileVersion: 1)
        
        Log.debug("Looking for file: \(fileName)")
        
        guard let found = lookupFile(forOwningTestAccount: owningUser, cloudFileName: fileName, options: options), !found else {
            XCTFail()
            return
        }
    }

    func testThatWriteSharingUserCanDownloadAFile() {
        downloadFileBySharingUser(withPermission: .write)
    }
    
    func testThatWriteSharingUserCanDownloadDeleteAFile() {
        downloadDeleteFileBySharingUser(withPermission: .write)
    }
    
    // MARK: Admin sharing user
    func testThatAdminSharingUserCanUploadAFile() {
        let sharingGroupUUID = UUID().uuidString
        let file: TestFile = .test1
        let mimeType: MimeType = file.mimeType
        
        guard let result = uploadFileBySharingUser(withPermission: .admin, owningAccount: .primaryOwningAccount, sharingGroupUUID: sharingGroupUUID, mimeType: mimeType, file: file) else {
            XCTFail()
            return
        }
        
        guard makeSureSharingOwnerOwnsUploadedFile(result: result, mimeType: mimeType.rawValue) else {
            XCTFail()
            return
        }
    }
    
    func testThatAdminSharingUserCanUploadDeleteAFile() {
        uploadDeleteFileBySharingUser(withPermission: .admin)
    }
    
    func testThatAdminSharingUserCanDownloadAFile() {
        downloadFileBySharingUser(withPermission: .admin)
    }
    
    func testThatAdminSharingUserCanDownloadDeleteAFile() {
        downloadDeleteFileBySharingUser(withPermission: .admin)
    }
    
    // MARK: Across sharing and owning users.
    func owningUserCanDownloadSharingUserFile(sharingUser: TestAccount = .primarySharingAccount) {
        let sharingGroupUUID = UUID().uuidString
        let file: TestFile = .test1
        let mimeType: MimeType = file.mimeType
        guard let result = uploadFileBySharingUser(withPermission: .write, owningAccount: .primaryOwningAccount, sharingUser: sharingUser, sharingGroupUUID: sharingGroupUUID, mimeType: mimeType, file: file) else {
            XCTFail()
            return
        }
        
        guard let _ = downloadFile(testAccount: sharingUser, fileUUID: result.request.fileUUID, fileVersion: 0, sharingGroupUUID: sharingGroupUUID, deviceUUID: result.uploadedDeviceUUID) else {
            XCTFail()
            return
        }
    }
    
    func testThatOwningUserCanDownloadSharingUserFile() {
        owningUserCanDownloadSharingUserFile()
    }
    
    func sharingUserCanDownloadSharingUserFile(sharingUser: TestAccount = .secondarySharingAccount) {
        // uploaded by primarySharingAccount
        let sharingGroupUUID = UUID().uuidString
        let file: TestFile = .test1
        let mimeType: MimeType = file.mimeType
        
        guard let result = uploadFileBySharingUser(withPermission: .write, owningAccount: .primaryOwningAccount, sharingGroupUUID: sharingGroupUUID, mimeType: mimeType, file: file) else {
            XCTFail()
            return
        }
        
        guard let sharingInvitationUUID = createSharingInvitation(permission: .read, sharingGroupUUID: sharingGroupUUID) else {
            XCTFail()
            return
        }
            
        // Redeem that sharing invitation with a new user
        guard let _ = redeemSharingInvitation(sharingUser: sharingUser, sharingInvitationUUID:sharingInvitationUUID) else {
            XCTFail()
            return
        }
            
        guard let _ = downloadFile(testAccount: sharingUser, fileUUID: result.request.fileUUID, fileVersion: 0, sharingGroupUUID: sharingGroupUUID, deviceUUID: result.uploadedDeviceUUID) else {
            XCTFail()
            return
        }
    }
    
    func testThatSharingUserCanDownloadSharingUserFile() {
        sharingUserCanDownloadSharingUserFile()
    }
    
    // After accepting a sharing invitation as an owning user (e.g., Google or Dropbox user), make sure auth tokens are stored, for that redeeming user, so that we can access cloud storage of that user.
    func testCanAccessCloudStorageOfRedeemingUser() {
        var sharingUserId: UserId!
        let sharingUser:TestAccount = .primarySharingAccount

        if sharingUser.scheme.userType == .owning {
            createSharingUser(sharingUser: sharingUser) { newUserId, _, _ in
                sharingUserId = newUserId
            }
            
            guard sharingUserId != nil else {
                XCTFail()
                return
            }
            
            // Reconstruct the creds of the sharing user and attempt to access their cloud storage.
            guard let cloudStorageCreds = FileController.getCreds(forUserId: sharingUserId, userRepo: UserRepository(db), accountManager: accountManager, accountDelegate: nil)?.cloudStorage(mock: MockStorage()) else {
                XCTFail()
                return
            }
            
            let exp = expectation(description: "test1")
            
            // It doesn't matter if the file here is found or not found; what matters is that the operation doesn't fail.
            let options = CloudStorageFileNameOptions(cloudFolderName: ServerTestCase.cloudFolderName, mimeType: "text/plain")
            cloudStorageCreds.lookupFile(cloudFileName: "foobar", options: options) { result in
                switch result {
                case .success(let result):
                    Log.debug("cloudStorageCreds.lookupFile: success: found: \(result)")
                    break
                case .failure(let error):
                    XCTFail("\(error)")
                case .accessTokenRevokedOrExpired:
                    XCTFail()
                }
                exp.fulfill()
            }
            
            waitForExpectations(timeout: 10, handler: nil)
        }
    }
    
    // User A invites B. B has cloud storage. B uploads. It goes to B's storage. Both A and B can download the file.
    func testUploadByOwningSharingUserThenDownloadByBothWorks() {
        let sharingAccount: TestAccount = .secondaryOwningAccount
        let sharingGroupUUID = UUID().uuidString
        let file: TestFile = .test1
        let mimeType: MimeType = file.mimeType
        
        guard let result = uploadFileBySharingUser(withPermission: .write, owningAccount: .primaryOwningAccount, sharingUser: sharingAccount, sharingGroupUUID: sharingGroupUUID, mimeType: mimeType, file: file) else {
            XCTFail()
            return
        }
        
        guard makeSureSharingOwnerOwnsUploadedFile(result: result, mimeType: mimeType.rawValue) else {
            XCTFail()
            return
        }

        guard let _ = downloadFile(testAccount: sharingAccount, fileUUID: result.request.fileUUID, fileVersion: 0, sharingGroupUUID: sharingGroupUUID, deviceUUID: result.uploadedDeviceUUID) else {
            XCTFail()
            return
        }
        
        guard let _ = downloadFile(testAccount: .primaryOwningAccount, fileUUID: result.request.fileUUID, fileVersion: 0, sharingGroupUUID: sharingGroupUUID, deviceUUID: result.uploadedDeviceUUID) else {
            XCTFail()
            return
        }
    }

    // Add a regular user. Invite a sharing user. Delete that regular user. See what happens if the sharing user tries to upload a file.
    func testUploadByOwningSharingUserAfterInvitingUserDeletedWorks() {
        var actualSharingGroupUUID:String!
        
        // Using an owning account here as sharing user because we always want the upload to work after deleting the inviting user.
        let sharingAccount: TestAccount = .secondaryOwningAccount
        
        createSharingUser(withSharingPermission: .write, sharingUser: sharingAccount) { userId, sharingGroupUUID, _ in
            actualSharingGroupUUID = sharingGroupUUID
        }
        
        guard actualSharingGroupUUID != nil else {
            XCTFail()
            return
        }
        
        let deviceUUID = Foundation.UUID().uuidString

        // remove the regular/inviting user
        performServerTest(testAccount: .primaryOwningAccount) { expectation, creds in
            let headers = self.setupHeaders(testUser: .primaryOwningAccount, accessToken: creds.accessToken, deviceUUID:deviceUUID)
            
            self.performRequest(route: ServerEndpoints.removeUser, headers: headers) { response, dict in
                Log.info("Status code: \(response!.statusCode)")
                XCTAssert(response!.statusCode == .OK, "removeUser failed")
                expectation.fulfill()
            }
        }
        
        // Attempting to upload a file by our sharing user-- this should work because the sharing user owns cloud storage.
        guard let _ = uploadTextFile(testAccount: sharingAccount, deviceUUID:deviceUUID, addUser: .no(sharingGroupUUID:actualSharingGroupUUID), fileLabel: UUID().uuidString) else {
            XCTFail()
            return
        }
    }
    
    func testUploadByNonOwningSharingUserAfterInvitingUserDeletedRespondsWithGone() {
        var actualSharingGroupUUID:String!
        
        let sharingAccount: TestAccount = .nonOwningSharingAccount
        let owningUserWhenCreating:TestAccount = .primaryOwningAccount
        
        createSharingUser(withSharingPermission: .write, sharingUser: sharingAccount, owningUserWhenCreating: owningUserWhenCreating) { userId, sharingGroupUUID, _ in
            actualSharingGroupUUID = sharingGroupUUID
        }
        
        guard actualSharingGroupUUID != nil else {
            XCTFail()
            return
        }
        
        let deviceUUID = Foundation.UUID().uuidString

        // remove the regular/inviting user
        performServerTest(testAccount: .primaryOwningAccount) { expectation, creds in
            let headers = self.setupHeaders(testUser: .primaryOwningAccount, accessToken: creds.accessToken, deviceUUID:deviceUUID)
            
            self.performRequest(route: ServerEndpoints.removeUser, headers: headers) { response, dict in
                Log.info("Status code: \(response!.statusCode)")
                XCTAssert(response!.statusCode == .OK, "removeUser failed")
                expectation.fulfill()
            }
        }
        

        // Attempting to upload a file by our sharing user-- this should fail with HTTP 410 (Gone) because the sharing user does not own cloud storage.
        let result = uploadTextFile(testAccount: sharingAccount, owningAccountType: owningUserWhenCreating.scheme.accountName, deviceUUID:deviceUUID, addUser: .no(sharingGroupUUID:actualSharingGroupUUID), fileLabel: UUID().uuidString, errorExpected: true, statusCodeExpected: HTTPStatusCode.gone)
        XCTAssert(result == nil)
    }
    
    // Similar to that above, but the non-owning, sharing user downloads a file-- that was owned by a third user, that is still on the system, and was in the same sharing group.
    func testDownloadFileOwnedByThirdUserAfterInvitingUserDeletedWorks() {
        var actualSharingGroupUUID:String!
        
        let sharingAccount1: TestAccount = .nonOwningSharingAccount
        
        // This account must be an owning account.
        let sharingAccount2: TestAccount = .secondaryOwningAccount
        
        createSharingUser(withSharingPermission: .write, sharingUser: sharingAccount1) { userId, sharingGroupUUID, _ in
            actualSharingGroupUUID = sharingGroupUUID
        }
        
        guard actualSharingGroupUUID != nil else {
            XCTFail()
            return
        }
        
        createSharingUser(withSharingPermission: .write, sharingUser: sharingAccount2, addUser: .no(sharingGroupUUID: actualSharingGroupUUID))
            
        let deviceUUID = Foundation.UUID().uuidString

        guard let uploadResult = uploadTextFile(testAccount: sharingAccount2, deviceUUID:deviceUUID, addUser: .no(sharingGroupUUID:actualSharingGroupUUID), fileLabel: UUID().uuidString) else {
            XCTFail()
            return
        }
                
        let deviceUUID2 = Foundation.UUID().uuidString

        // remove the regular/inviting user
        performServerTest(testAccount: .primaryOwningAccount) { expectation, creds in
            let headers = self.setupHeaders(testUser: .primaryOwningAccount, accessToken: creds.accessToken, deviceUUID:deviceUUID2)
            
            self.performRequest(route: ServerEndpoints.removeUser, headers: headers) { response, dict in
                Log.info("Status code: \(response!.statusCode)")
                XCTAssert(response!.statusCode == .OK, "removeUser failed")
                expectation.fulfill()
            }
        }
        
        guard let _ = downloadFile(testAccount: sharingAccount1, fileUUID: uploadResult.request.fileUUID, fileVersion: 0, sharingGroupUUID: actualSharingGroupUUID, deviceUUID: deviceUUID2) else {
            XCTFail()
            return
        }
    }
    
    // File operations work for a second sharing group you are a member of: Upload
    func testThatUploadForSecondSharingGroupWorks() {
        let owningAccount: TestAccount = .primaryOwningAccount
        guard let (sharingAccount, sharingGroupUUID) = redeemWithAnExistingOtherSharingAccount() else {
            XCTFail()
            return
        }
        
        var owningAccountType: AccountScheme.AccountName?
        if sharingAccount.scheme.userType == .owning {
            owningAccountType = sharingAccount.scheme.accountName
        }
        else {
            owningAccountType = owningAccount.scheme.accountName
        }
        
        guard let _ = uploadTextFile(testAccount: sharingAccount, owningAccountType: owningAccountType, addUser: .no(sharingGroupUUID:sharingGroupUUID), fileLabel: UUID().uuidString) else {
            XCTFail()
            return
        }
    }
    
    func testThatDoneUploadsForSecondSharingGroupWorks() {
        let owningAccount: TestAccount = .primaryOwningAccount
        guard let (sharingAccount, sharingGroupUUID) = redeemWithAnExistingOtherSharingAccount() else {
            XCTFail()
            return
        }
        
        var owningAccountType: AccountScheme.AccountName?
        if sharingAccount.scheme.userType == .owning {
            owningAccountType = sharingAccount.scheme.accountName
        }
        else {
            owningAccountType = owningAccount.scheme.accountName
        }
        
        let deviceUUID = Foundation.UUID().uuidString
        guard let _ = uploadTextFile(testAccount: sharingAccount, owningAccountType: owningAccountType, deviceUUID: deviceUUID, addUser: .no(sharingGroupUUID:sharingGroupUUID), fileLabel: UUID().uuidString) else {
            XCTFail()
            return
        }
    }

    func testThatDownloadForSecondSharingGroupWorks() {
        let owningAccount: TestAccount = .primaryOwningAccount
        guard let (sharingAccount, sharingGroupUUID) = redeemWithAnExistingOtherSharingAccount() else {
            XCTFail()
            return
        }
        
        var owningAccountType: AccountScheme.AccountName?
        if sharingAccount.scheme.userType == .owning {
            owningAccountType = sharingAccount.scheme.accountName
        }
        else {
            owningAccountType = owningAccount.scheme.accountName
        }
        
        let deviceUUID = Foundation.UUID().uuidString
        guard let result = uploadTextFile(testAccount: sharingAccount, owningAccountType: owningAccountType, deviceUUID: deviceUUID, addUser: .no(sharingGroupUUID:sharingGroupUUID), fileLabel: UUID().uuidString) else {
            XCTFail()
            return
        }
        
        guard let _ = downloadFile(testAccount: sharingAccount, fileUUID: result.request.fileUUID, fileVersion: 0, sharingGroupUUID: sharingGroupUUID, deviceUUID: deviceUUID) else {
            XCTFail()
            return
        }
    }
}

