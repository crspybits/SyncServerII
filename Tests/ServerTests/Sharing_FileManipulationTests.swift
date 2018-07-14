//
//  Sharing_FileManipulationTests.swift
//  Server
//
//  Created by Christopher Prince on 4/15/17.
//
//

import XCTest
@testable import Server
import LoggerAPI
import Foundation
import SyncServerShared
import Kitura

class Sharing_FileManipulationTests: ServerTestCase, LinuxTestable {

    override func setUp() {
        super.setUp()
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }
    
    override func tearDown() {
        super.tearDown()
    }
    
    struct SharingUploadResult {
        let request: UploadFileRequest
        let fileSize:Int64
        let sharingGroupId: SharingGroupId
        let sharingTestAccount:TestAccount
        let uploadedDeviceUUID: String
        let redeemResponse: RedeemSharingInvitationResponse
    }
    
    // If not adding a user, you must pass a sharingGroupId.
    @discardableResult
    func uploadFileBySharingUser(withPermission sharingPermission:Permission, sharingUser: TestAccount = .primarySharingAccount, addUser: Bool = true, sharingGroupId: SharingGroupId? = nil, failureExpected:Bool = false, fileUUID:String? = nil, fileVersion:FileVersionInt = 0, masterVersion: MasterVersionInt = 0) -> SharingUploadResult? {
        let deviceUUID1 = Foundation.UUID().uuidString
        
        var actualSharingGroupId: SharingGroupId!
        
        if addUser {
            guard let addUserResponse = addNewUser(deviceUUID:deviceUUID1),
                let sharingGroupId = addUserResponse.sharingGroupId else {
                XCTFail()
                return nil
            }
            
            actualSharingGroupId = sharingGroupId
        }
        else {
            actualSharingGroupId = sharingGroupId
        }
        
        var sharingInvitationUUID:String!
        
        // Have that newly created user create a sharing invitation.
        createSharingInvitation(permission: sharingPermission, sharingGroupId:actualSharingGroupId) { expectation, invitationUUID in
            sharingInvitationUUID = invitationUUID!
            expectation.fulfill()
        }
        
        var redeemResponse: RedeemSharingInvitationResponse!
        
        // Redeem that sharing invitation with a new user
        redeemSharingInvitation(sharingUser: sharingUser, sharingInvitationUUID:sharingInvitationUUID) { result, expectation in
            redeemResponse = result
            expectation.fulfill()
        }
        
        guard redeemResponse != nil else {
            XCTFail()
            return nil
        }
        
        let deviceUUID2 = Foundation.UUID().uuidString
        
        // Attempting to upload a file by our sharing user
        guard let uploadResult = uploadTextFile(testAccount: sharingUser, deviceUUID:deviceUUID2, fileUUID: fileUUID, addUser: .no(sharingGroupId:actualSharingGroupId), fileVersion: fileVersion, masterVersion: masterVersion, errorExpected: failureExpected) else {
            XCTFail()
            return nil
        }
        
        sendDoneUploads(testAccount: sharingUser, expectedNumberOfUploads: 1, deviceUUID:deviceUUID2, masterVersion: masterVersion, sharingGroupId: actualSharingGroupId, failureExpected: failureExpected)
        
        return SharingUploadResult(request: uploadResult.request, fileSize: uploadResult.fileSize, sharingGroupId: actualSharingGroupId, sharingTestAccount: sharingUser, uploadedDeviceUUID:deviceUUID2, redeemResponse: redeemResponse)
    }
    
    func uploadDeleteFileBySharingUser(withPermission sharingPermission:Permission, sharingUser: TestAccount = .primarySharingAccount, failureExpected:Bool = false) {
        let deviceUUID1 = Foundation.UUID().uuidString
        
        guard let addUserResponse = addNewUser(testAccount: .primaryOwningAccount, deviceUUID:deviceUUID1),
            let sharingGroupId = addUserResponse.sharingGroupId else {
            XCTFail()
            return
        }
        
        // And upload a file by that user.
        guard let uploadResult = uploadTextFile(testAccount: .primaryOwningAccount, deviceUUID:deviceUUID1, addUser:.no(sharingGroupId: sharingGroupId)) else {
            XCTFail()
            return
        }
        
        sendDoneUploads(testAccount: .primaryOwningAccount, expectedNumberOfUploads: 1, deviceUUID:deviceUUID1, sharingGroupId:sharingGroupId)
        
        var sharingInvitationUUID:String!
        
        // Have that newly created user create a sharing invitation.
        createSharingInvitation(permission: sharingPermission, sharingGroupId:sharingGroupId) { expectation, invitationUUID in
            sharingInvitationUUID = invitationUUID!
            expectation.fulfill()
        }
        
        // Redeem that sharing invitation with a new user
        redeemSharingInvitation(sharingUser: sharingUser, sharingInvitationUUID:sharingInvitationUUID) { _, expectation in
            expectation.fulfill()
        }
        
        let deviceUUID2 = Foundation.UUID().uuidString

        let uploadDeletionRequest = UploadDeletionRequest(json: [
            UploadDeletionRequest.fileUUIDKey: uploadResult.request.fileUUID,
            UploadDeletionRequest.fileVersionKey: uploadResult.request.fileVersion,
            UploadDeletionRequest.masterVersionKey: uploadResult.request.masterVersion + MasterVersionInt(1),
            ServerEndpoint.sharingGroupIdKey: sharingGroupId
        ])!
        
        uploadDeletion(testAccount: sharingUser, uploadDeletionRequest: uploadDeletionRequest, deviceUUID: deviceUUID2, addUser: false, expectError: failureExpected)
        sendDoneUploads(testAccount: sharingUser, expectedNumberOfUploads: 1, deviceUUID:deviceUUID2, masterVersion: uploadResult.request.masterVersion + MasterVersionInt(1), sharingGroupId: sharingGroupId, failureExpected:failureExpected)
    }
    
    func downloadFileBySharingUser(withPermission sharingPermission:Permission, sharingUser: TestAccount = .primarySharingAccount, failureExpected:Bool = false) {
        let deviceUUID1 = Foundation.UUID().uuidString
        
        guard let addUserResponse = addNewUser(testAccount: .primaryOwningAccount, deviceUUID:deviceUUID1),
            let sharingGroupId = addUserResponse.sharingGroupId else {
            XCTFail()
            return
        }
        
        // And upload a file by that user.
        guard let uploadResult = uploadTextFile(testAccount: .primaryOwningAccount, deviceUUID:deviceUUID1, addUser:.no(sharingGroupId: sharingGroupId)) else {
            XCTFail()
            return
        }
        
        sendDoneUploads(testAccount: .primaryOwningAccount, expectedNumberOfUploads: 1, deviceUUID:deviceUUID1, sharingGroupId: sharingGroupId)
        
        var sharingInvitationUUID:String!
        
        // Have that newly created user create a sharing invitation.
        createSharingInvitation(permission: sharingPermission, sharingGroupId:sharingGroupId) { expectation, invitationUUID in
            sharingInvitationUUID = invitationUUID!
            expectation.fulfill()
        }
        
        redeemSharingInvitation(sharingUser: sharingUser, sharingInvitationUUID:sharingInvitationUUID) { _, expectation in
            expectation.fulfill()
        }
        
        // Now see if we can download the file with the sharing user creds.
        downloadTextFile(testAccount: sharingUser, masterVersionExpectedWithDownload: 1, uploadFileRequest: uploadResult.request, fileSize: uploadResult.fileSize, expectedError:failureExpected)
    }
    
    func downloadDeleteFileBySharingUser(withPermission sharingPermission:Permission, sharingUser: TestAccount = .primarySharingAccount, failureExpected:Bool = false) {
    
        let deviceUUID1 = Foundation.UUID().uuidString
        
        guard let addUserResponse = addNewUser(testAccount: .primaryOwningAccount, deviceUUID:deviceUUID1),
            let sharingGroupId = addUserResponse.sharingGroupId else {
            XCTFail()
            return
        }
        
        // And upload a file by that user.
        guard let uploadResult = uploadTextFile(testAccount: .primaryOwningAccount, deviceUUID:deviceUUID1, addUser:.no(sharingGroupId: sharingGroupId)) else {
            XCTFail()
            return
        }
        sendDoneUploads(testAccount: .primaryOwningAccount, expectedNumberOfUploads: 1, deviceUUID:deviceUUID1, sharingGroupId: sharingGroupId)
        
        let uploadDeletionRequest = UploadDeletionRequest(json: [
            UploadDeletionRequest.fileUUIDKey: uploadResult.request.fileUUID,
            UploadDeletionRequest.fileVersionKey: uploadResult.request.fileVersion,
            UploadDeletionRequest.masterVersionKey: uploadResult.request.masterVersion + MasterVersionInt(1),
            ServerEndpoint.sharingGroupIdKey: sharingGroupId
        ])!
        
        uploadDeletion(uploadDeletionRequest: uploadDeletionRequest, deviceUUID: deviceUUID1, addUser: false, expectError: failureExpected)
        sendDoneUploads(expectedNumberOfUploads: 1, deviceUUID:deviceUUID1, masterVersion: uploadResult.request.masterVersion + MasterVersionInt(1), sharingGroupId: sharingGroupId, failureExpected:failureExpected)
        
        var sharingInvitationUUID:String!
        
        // Have that newly created user create a sharing invitation.
        createSharingInvitation(permission: sharingPermission, sharingGroupId:sharingGroupId) { expectation, invitationUUID in
            sharingInvitationUUID = invitationUUID!
            expectation.fulfill()
        }
        
        // Redeem that sharing invitation with a new user
        redeemSharingInvitation(sharingUser: sharingUser, sharingInvitationUUID:sharingInvitationUUID) { _, expectation in
            expectation.fulfill()
        }
    
        // The final step of a download deletion is to check the file index-- and make sure it's marked as deleted for us.
        
        let deviceUUID2 = Foundation.UUID().uuidString
        
        guard let fileIndex = getFileIndex(testAccount: sharingUser, deviceUUID:deviceUUID2, sharingGroupId: sharingGroupId), fileIndex.count == 1 else {
            XCTFail()
            return
        }
        
        XCTAssert(fileIndex[0].deleted == true)
    }
    
    // MARK: Read sharing user
    func testThatReadSharingUserCannotUploadAFile() {
        guard let _ = uploadFileBySharingUser(withPermission: .read, failureExpected:true) else {
            XCTFail()
            return
        }
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
    
    func checkFileOwner(uploadedDeviceUUID: String, owningAccount: TestAccount, ownerUserId: UserId, request: UploadFileRequest) {
        let options = CloudStorageFileNameOptions(cloudFolderName: ServerTestCase.cloudFolderName, mimeType: request.mimeType)

        let fileName = request.cloudFileName(deviceUUID:uploadedDeviceUUID, mimeType: request.mimeType)
        Log.debug("Looking for file: \(fileName)")
        guard let found = lookupFile(testAccount: owningAccount, cloudFileName: fileName, options: options), found else {
            XCTFail()
            return
        }
    
        let key = FileIndexRepository.LookupKey.primaryKeys(sharingGroupId: request.sharingGroupId, fileUUID: request.fileUUID)
        guard case .found(let obj) = FileIndexRepository(db).lookup(key: key, modelInit: FileIndex.init), let fileIndexObj = obj as? FileIndex else {
            XCTFail()
            return
        }

        XCTAssert(fileIndexObj.userId == ownerUserId)
    }

    // Check to make sure that if the invited user owns cloud storage that the file was uploaded to their cloud storage.
    func makeSureSharingOwnerOwnsUploadedFile(result: SharingUploadResult) {
        if result.sharingTestAccount.type.userType == .owning {
            checkFileOwner(uploadedDeviceUUID: result.uploadedDeviceUUID, owningAccount: result.sharingTestAccount, ownerUserId: result.redeemResponse.userId, request: result.request)
        }
    }
    
    // MARK: Write sharing user
    func testThatWriteSharingUserCanUploadAFile() {
        guard let result = uploadFileBySharingUser(withPermission: .write) else {
            XCTFail()
            return
        }
        
        makeSureSharingOwnerOwnsUploadedFile(result: result)
    }
    
    // When an owning user uploads a modified file (v1) which was initially uploaded (v0) by another owning user, that original owning user must remain the owner of the modified file.
    func testThatV0FileOwnerRemainsFileOwner() {
        // Upload v0 of file.
        let deviceUUID = Foundation.UUID().uuidString
        guard let uploadResult = uploadTextFile(deviceUUID:deviceUUID),
            let sharingGroupId = uploadResult.sharingGroupId,
            let v0UserId = uploadResult.uploadingUserId else {
            XCTFail()
            return
        }
        
        // Upload v1 of file by another user
        self.sendDoneUploads(expectedNumberOfUploads: 1, deviceUUID:deviceUUID, sharingGroupId: sharingGroupId)
        
        guard let uploadResult2 = uploadFileBySharingUser(withPermission: .write, addUser: false, sharingGroupId: sharingGroupId, fileUUID: uploadResult.request.fileUUID, fileVersion: 1, masterVersion: 1) else {
            XCTFail()
            return
        }
        
        // Check that the v0 owner still owns the file.
        checkFileOwner(uploadedDeviceUUID: uploadResult2.uploadedDeviceUUID, owningAccount: .primaryOwningAccount, ownerUserId: v0UserId, request: uploadResult2.request)
    }
    
    func testThatWriteSharingUserCanUploadDeleteAFile() {
        uploadDeleteFileBySharingUser(withPermission: .write)
    }
    
    // Upload deletion, including DoneUploads, with files with v0 owners that are different.
    func testUploadDeletionWithDifferentV0OwnersWorks() {
        // Upload v0 of file by .primaryOwningAccount user
        var masterVersion: MasterVersionInt = 0
        let deviceUUID = Foundation.UUID().uuidString
        guard let upload1 = uploadTextFile(deviceUUID:deviceUUID),
            let sharingGroupId = upload1.sharingGroupId else {
            XCTFail()
            return
        }
        
        sendDoneUploads(expectedNumberOfUploads: 1, deviceUUID:deviceUUID, masterVersion: masterVersion, sharingGroupId: sharingGroupId)
        
        masterVersion += 1
        
        guard let upload2 = uploadFileBySharingUser(withPermission: .write, addUser: false, sharingGroupId: sharingGroupId, masterVersion: masterVersion) else {
            XCTFail()
            return
        }

        masterVersion += 1
        
        let uploadDeletionRequest1 = UploadDeletionRequest(json: [
            UploadDeletionRequest.fileUUIDKey: upload1.request.fileUUID,
            UploadDeletionRequest.fileVersionKey: upload1.request.fileVersion,
            UploadDeletionRequest.masterVersionKey: masterVersion,
            ServerEndpoint.sharingGroupIdKey: sharingGroupId
        ])!

        uploadDeletion(testAccount: upload2.sharingTestAccount, uploadDeletionRequest: uploadDeletionRequest1, deviceUUID: deviceUUID, addUser: false)

        let uploadDeletionRequest2 = UploadDeletionRequest(json: [
            UploadDeletionRequest.fileUUIDKey: upload2.request.fileUUID,
            UploadDeletionRequest.fileVersionKey: upload2.request.fileVersion,
            UploadDeletionRequest.masterVersionKey: masterVersion,
            ServerEndpoint.sharingGroupIdKey: sharingGroupId
        ])!

        uploadDeletion(testAccount: upload2.sharingTestAccount, uploadDeletionRequest: uploadDeletionRequest2, deviceUUID: deviceUUID, addUser: false)

        sendDoneUploads(testAccount: upload2.sharingTestAccount, expectedNumberOfUploads: 2, deviceUUID:deviceUUID, masterVersion: masterVersion, sharingGroupId: sharingGroupId)
    }
    
    // Upload deletions must go to the account of the original (v0) owning user. To test this: a) upload v0 of a file, b) have a different user upload v1 of the file. Now upload delete. Make sure the deletion works.
    func testThatUploadDeletionOfFileAfterV1UploadBySharingUserWorks() {
        // Upload v0 of file.
        let deviceUUID = Foundation.UUID().uuidString
        guard let uploadResult = uploadTextFile(deviceUUID:deviceUUID),
            let sharingGroupId = uploadResult.sharingGroupId else {
            XCTFail()
            return
        }
        
        // Upload v1 of file by another user
        self.sendDoneUploads(expectedNumberOfUploads: 1, deviceUUID:deviceUUID, sharingGroupId: sharingGroupId)
        
        var masterVersion: MasterVersionInt = 1
        
        guard let _ = uploadFileBySharingUser(withPermission: .write, addUser: false, sharingGroupId: sharingGroupId, fileUUID: uploadResult.request.fileUUID, fileVersion: 1, masterVersion: masterVersion) else {
            XCTFail()
            return
        }
        
        masterVersion += 1
        
        let uploadDeletionRequest = UploadDeletionRequest(json: [
            UploadDeletionRequest.fileUUIDKey: uploadResult.request.fileUUID,
            UploadDeletionRequest.fileVersionKey: 1,
            UploadDeletionRequest.masterVersionKey: masterVersion,
            ServerEndpoint.sharingGroupIdKey: sharingGroupId
        ])!
        
        // Original v0 uploader deletes file.
        uploadDeletion(testAccount: .primaryOwningAccount, uploadDeletionRequest: uploadDeletionRequest, deviceUUID: deviceUUID, addUser: false)
        sendDoneUploads(testAccount: .primaryOwningAccount, expectedNumberOfUploads: 1, deviceUUID:deviceUUID, masterVersion: masterVersion, sharingGroupId: sharingGroupId)
    }
    
    // Make sure file actually gets deleted in cloud storage for non-root owning users.
    func testUploadDeletionForNonRootOwningUserWorks() {
        guard let result = uploadFileBySharingUser(withPermission: .write) else {
            XCTFail()
            return
        }
        
        let masterVersion: MasterVersionInt = 1
        
        let uploadDeletionRequest = UploadDeletionRequest(json: [
            UploadDeletionRequest.fileUUIDKey: result.request.fileUUID,
            UploadDeletionRequest.fileVersionKey: 0,
            UploadDeletionRequest.masterVersionKey: masterVersion,
            ServerEndpoint.sharingGroupIdKey: result.sharingGroupId
        ])!
        
        // Original v0 uploader deletes file.
        uploadDeletion(testAccount: result.sharingTestAccount, uploadDeletionRequest: uploadDeletionRequest, deviceUUID: result.uploadedDeviceUUID, addUser: false)
        sendDoneUploads(testAccount: result.sharingTestAccount, expectedNumberOfUploads: 1, deviceUUID:result.uploadedDeviceUUID, masterVersion: masterVersion, sharingGroupId: result.sharingGroupId)

        let options = CloudStorageFileNameOptions(cloudFolderName: ServerTestCase.cloudFolderName, mimeType: result.request.mimeType)

        let fileName = result.request.cloudFileName(deviceUUID:result.uploadedDeviceUUID, mimeType: result.request.mimeType)
        Log.debug("Looking for file: \(fileName)")
        guard let found = lookupFile(testAccount: result.sharingTestAccount, cloudFileName: fileName, options: options), !found else {
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
        guard let result = uploadFileBySharingUser(withPermission: .admin) else {
            XCTFail()
            return
        }
        
        makeSureSharingOwnerOwnsUploadedFile(result: result)
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
        guard let result = uploadFileBySharingUser(withPermission: .write, sharingUser: sharingUser) else {
            XCTFail()
            return
        }
        
        downloadTextFile(testAccount: .primaryOwningAccount, masterVersionExpectedWithDownload: 1, uploadFileRequest: result.request, fileSize: result.fileSize, expectedError:false)
    }
    
    func testThatOwningUserCanDownloadSharingUserFile() {
        owningUserCanDownloadSharingUserFile()
    }
    
    func sharingUserCanDownloadSharingUserFile(sharingUser: TestAccount = .secondarySharingAccount) {
        // uploaded by primarySharingAccount
        guard let result = uploadFileBySharingUser(withPermission: .write) else {
            XCTFail()
            return
        }
            
        var sharingInvitationUUID:String!
            
        createSharingInvitation(permission: .read, sharingGroupId: result.sharingGroupId) { expectation, invitationUUID in
            sharingInvitationUUID = invitationUUID!
            expectation.fulfill()
        }
            
        // Redeem that sharing invitation with a new user
        redeemSharingInvitation(sharingUser: sharingUser, sharingInvitationUUID:sharingInvitationUUID) { _, expectation in
            expectation.fulfill()
        }
            
        downloadTextFile(testAccount: sharingUser, masterVersionExpectedWithDownload: 1, uploadFileRequest: result.request, fileSize: result.fileSize, expectedError:false)
    }
    
    func testThatSharingUserCanDownloadSharingUserFile() {
        sharingUserCanDownloadSharingUserFile()
    }
    
    // After accepting a sharing invitation as a Google or Dropbox user, make sure auth tokens are stored, for that redeeming user, so that we can access cloud storage of that user.
    func testCanAccessCloudStorageOfRedeemingUser() {
        var userId: UserId!
        createSharingUser(sharingUser: .primarySharingAccount) { newUserId, sharingGroupId in
            userId = newUserId
        }
        
        // Reconstruct the creds of the sharing user and attempt to access their cloud storage.
        guard userId != nil, let cloudStorageCreds = FileController.getCreds(forUserId: userId, from: db) as? CloudStorage else {
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
            }
            exp.fulfill()
        }
        
        waitForExpectations(timeout: 10, handler: nil)
    }
    
    // Add a regular user. Invite a sharing user. Delete that regular user. See what happens if the sharing user tries to upload a file.
    func testUploadByOwningSharingUserAfterInvitingUserDeletedWorks() {
        var actualSharingGroupId:SharingGroupId!
        
        // Using an owning account here as sharing user because we always want the upload to work after deleting the inviting user.
        let sharingAccount: TestAccount = .secondaryOwningAccount
        
        createSharingUser(withSharingPermission: .write, sharingUser: sharingAccount) { userId, sharingGroupId in
            actualSharingGroupId = sharingGroupId
        }
        
        guard actualSharingGroupId != nil else {
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
        guard let _ = uploadTextFile(testAccount: sharingAccount, deviceUUID:deviceUUID, addUser: .no(sharingGroupId:actualSharingGroupId)) else {
            XCTFail()
            return
        }
    }
    
    // User A invites B. B has cloud storage. B uploads. It goes to B's storage. Both A and B can download the file.
    func testUploadByOwningSharingUserThenDownloadByBothWorks() {
        let sharingAccount: TestAccount = .secondaryOwningAccount
        
        guard let result = uploadFileBySharingUser(withPermission: .write, sharingUser: sharingAccount) else {
            XCTFail()
            return
        }
        
        makeSureSharingOwnerOwnsUploadedFile(result: result)

        guard let _ = downloadTextFile(testAccount: sharingAccount, masterVersionExpectedWithDownload: 1, uploadFileRequest: result.request, fileSize: result.fileSize) else {
            XCTFail()
            return
        }
        
        guard let _ = downloadTextFile(testAccount: .primaryOwningAccount, masterVersionExpectedWithDownload: 1, uploadFileRequest: result.request, fileSize: result.fileSize) else {
            XCTFail()
            return
        }
    }
    
    func testUploadByNonOwningSharingUserAfterInvitingUserDeletedFails() {
        var actualSharingGroupId:SharingGroupId!
        
        let sharingAccount: TestAccount = .nonOwningSharingAccount
        
        createSharingUser(withSharingPermission: .write, sharingUser: sharingAccount) { userId, sharingGroupId in
            actualSharingGroupId = sharingGroupId
        }
        
        guard actualSharingGroupId != nil else {
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
        uploadTextFile(testAccount: sharingAccount, deviceUUID:deviceUUID, addUser: .no(sharingGroupId:actualSharingGroupId), errorExpected: true, statusCodeExpected: HTTPStatusCode.gone)
    }
    
    // Similar to that above, but the non-owning, sharing user downloads a file-- that was owned by a third user, that is still on the system, and was in the same sharing group.
    func testDownloadFileOwnedByThirdUserAfterInvitingUserDeletedWorks() {
        var actualSharingGroupId:SharingGroupId!
        
        let sharingAccount1: TestAccount = .nonOwningSharingAccount
        
        // This account must be an owning account.
        let sharingAccount2: TestAccount = .secondaryOwningAccount
        
        createSharingUser(withSharingPermission: .write, sharingUser: sharingAccount1) { userId, sharingGroupId in
            actualSharingGroupId = sharingGroupId
        }
        
        createSharingUser(withSharingPermission: .write, sharingUser: sharingAccount2, addUser: .no(sharingGroupId: actualSharingGroupId))
    
        let deviceUUID = Foundation.UUID().uuidString

        guard let uploadResult = uploadTextFile(testAccount: sharingAccount2, deviceUUID:deviceUUID, addUser: .no(sharingGroupId:actualSharingGroupId)) else {
            XCTFail()
            return
        }
        
        self.sendDoneUploads(testAccount: sharingAccount2, expectedNumberOfUploads: 1, deviceUUID:deviceUUID, sharingGroupId: actualSharingGroupId)
        
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
        
        guard let _ = downloadTextFile(testAccount: sharingAccount1, masterVersionExpectedWithDownload: 1, uploadFileRequest: uploadResult.request, fileSize: uploadResult.fileSize) else {
            XCTFail()
            return
        }
    }
}

extension Sharing_FileManipulationTests {
    static var allTests : [(String, (Sharing_FileManipulationTests) -> () throws -> Void)] {
        return [
            ("testThatReadSharingUserCannotUploadAFile", testThatReadSharingUserCannotUploadAFile),
            ("testThatReadSharingUserCannotUploadDeleteAFile", testThatReadSharingUserCannotUploadDeleteAFile),
            ("testThatReadSharingUserCanDownloadAFile", testThatReadSharingUserCanDownloadAFile),
            ("testThatReadSharingUserCanDownloadDeleteAFile", testThatReadSharingUserCanDownloadDeleteAFile),
            ("testThatWriteSharingUserCanUploadAFile", testThatWriteSharingUserCanUploadAFile),
            ("testThatV0FileOwnerRemainsFileOwner", testThatV0FileOwnerRemainsFileOwner),
            ("testUploadDeletionWithDifferentV0OwnersWorks",
                testUploadDeletionWithDifferentV0OwnersWorks),
            ("testUploadByOwningSharingUserThenDownloadByBothWorks",
                testUploadByOwningSharingUserThenDownloadByBothWorks),
            ("testThatUploadDeletionOfFileAfterV1UploadBySharingUserWorks", testThatUploadDeletionOfFileAfterV1UploadBySharingUserWorks),
            ("testUploadDeletionForNonRootOwningUserWorks", testUploadDeletionForNonRootOwningUserWorks),
            ("testThatWriteSharingUserCanUploadDeleteAFile", testThatWriteSharingUserCanUploadDeleteAFile),
            ("testThatWriteSharingUserCanDownloadAFile", testThatWriteSharingUserCanDownloadAFile),
            ("testThatWriteSharingUserCanDownloadDeleteAFile", testThatWriteSharingUserCanDownloadDeleteAFile),
            ("testThatAdminSharingUserCanUploadAFile", testThatAdminSharingUserCanUploadAFile),
            ("testThatAdminSharingUserCanUploadDeleteAFile", testThatAdminSharingUserCanUploadDeleteAFile),
            ("testThatAdminSharingUserCanDownloadAFile", testThatAdminSharingUserCanDownloadAFile),
            ("testThatAdminSharingUserCanDownloadDeleteAFile", testThatAdminSharingUserCanDownloadDeleteAFile),
            ("testThatOwningUserCanDownloadSharingUserFile", testThatOwningUserCanDownloadSharingUserFile),
            ("testThatSharingUserCanDownloadSharingUserFile", testThatSharingUserCanDownloadSharingUserFile),
            ("testCanAccessCloudStorageOfRedeemingUser", testCanAccessCloudStorageOfRedeemingUser),
            ("testUploadByOwningSharingUserAfterInvitingUserDeletedWorks",
                testUploadByOwningSharingUserAfterInvitingUserDeletedWorks),
            ("testUploadByNonOwningSharingUserAfterInvitingUserDeletedFails",
                testUploadByNonOwningSharingUserAfterInvitingUserDeletedFails),
            ("testDownloadFileOwnedByThirdUserAfterInvitingUserDeletedWorks",
                testDownloadFileOwnedByThirdUserAfterInvitingUserDeletedWorks)
        ]
    }
    
    func testLinuxTestSuiteIncludesAllTests() {
        linuxTestSuiteIncludesAllTests(testType:Sharing_FileManipulationTests.self)
    }
}

