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
        let checkSum:String
        let sharingTestAccount:TestAccount
        let uploadedDeviceUUID: String
        let redeemResponse: RedeemSharingInvitationResponse
    }
    
    // If not adding a user, you must pass a sharingGroupUUID.
    @discardableResult
    func uploadFileBySharingUser(withPermission sharingPermission:Permission, owningAccount: TestAccount, sharingUser: TestAccount = .primarySharingAccount, addUser: Bool = true, sharingGroupUUID: String, failureExpected:Bool = false, fileUUID:String? = nil, fileVersion:FileVersionInt = 0, masterVersion: MasterVersionInt = 0) -> SharingUploadResult? {
        let deviceUUID1 = Foundation.UUID().uuidString
        
        if addUser {
            guard let _ = addNewUser(testAccount: owningAccount, sharingGroupUUID: sharingGroupUUID, deviceUUID:deviceUUID1) else {
                XCTFail()
                return nil
            }
        }
        
        var sharingInvitationUUID:String!
        
        // Have that newly created user create a sharing invitation.
        createSharingInvitation(testAccount: owningAccount, permission: sharingPermission, sharingGroupUUID:sharingGroupUUID) { expectation, invitationUUID in
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
        
        var owningAccountType: AccountType
        
        if fileVersion == 0 {
            switch sharingUser.type.userType {
            case .owning:
                owningAccountType = sharingUser.type
            case .sharing:
                owningAccountType = owningAccount.type
            }
        }
        else {
            owningAccountType = owningAccount.type
        }
        
        // Attempting to upload a file by our sharing user
        guard let uploadResult = uploadTextFile(testAccount: sharingUser, owningAccountType: owningAccountType, deviceUUID:deviceUUID2, fileUUID: fileUUID, addUser: .no(sharingGroupUUID:sharingGroupUUID), fileVersion: fileVersion, masterVersion: masterVersion + 1, errorExpected: failureExpected) else {
            if !failureExpected {
                XCTFail()
            }
            return nil
        }
        
        sendDoneUploads(testAccount: sharingUser, expectedNumberOfUploads: 1, deviceUUID:deviceUUID2, masterVersion: masterVersion + 1, sharingGroupUUID: sharingGroupUUID, failureExpected: failureExpected)
        
        return SharingUploadResult(request: uploadResult.request, checkSum: uploadResult.checkSum,  sharingTestAccount: sharingUser, uploadedDeviceUUID:deviceUUID2, redeemResponse: redeemResponse)
    }
    
    func uploadDeleteFileBySharingUser(withPermission sharingPermission:Permission, sharingUser: TestAccount = .primarySharingAccount, failureExpected:Bool = false) {
        let deviceUUID1 = Foundation.UUID().uuidString
        let sharingGroupUUID = Foundation.UUID().uuidString

        guard let _ = addNewUser(testAccount: .primaryOwningAccount, sharingGroupUUID: sharingGroupUUID, deviceUUID:deviceUUID1) else {
            XCTFail()
            return
        }
        
        // And upload a file by that user.
        guard let uploadResult = uploadTextFile(testAccount: .primaryOwningAccount, deviceUUID:deviceUUID1, addUser:.no(sharingGroupUUID: sharingGroupUUID)) else {
            XCTFail()
            return
        }
        
        sendDoneUploads(testAccount: .primaryOwningAccount, expectedNumberOfUploads: 1, deviceUUID:deviceUUID1, sharingGroupUUID:sharingGroupUUID)
        
        var sharingInvitationUUID:String!
        
        // Have that newly created user create a sharing invitation.
        createSharingInvitation(permission: sharingPermission, sharingGroupUUID:sharingGroupUUID) { expectation, invitationUUID in
            sharingInvitationUUID = invitationUUID!
            expectation.fulfill()
        }
        
        guard let masterVersion = getMasterVersion(sharingGroupUUID: sharingGroupUUID) else {
            XCTFail()
            return
        }

        // Redeem that sharing invitation with a new user
        redeemSharingInvitation(sharingUser: sharingUser, sharingInvitationUUID:sharingInvitationUUID) { _, expectation in
            expectation.fulfill()
        }
        
        let deviceUUID2 = Foundation.UUID().uuidString

        let uploadDeletionRequest = UploadDeletionRequest(json: [
            UploadDeletionRequest.fileUUIDKey: uploadResult.request.fileUUID,
            UploadDeletionRequest.fileVersionKey: uploadResult.request.fileVersion,
            UploadDeletionRequest.masterVersionKey: masterVersion + 1,
            ServerEndpoint.sharingGroupUUIDKey: sharingGroupUUID
        ])!
        
        uploadDeletion(testAccount: sharingUser, uploadDeletionRequest: uploadDeletionRequest, deviceUUID: deviceUUID2, addUser: false, expectError: failureExpected)
        sendDoneUploads(testAccount: sharingUser, expectedNumberOfUploads: 1, deviceUUID:deviceUUID2, masterVersion: masterVersion + 1, sharingGroupUUID: sharingGroupUUID, failureExpected:failureExpected)
    }
    
    func downloadFileBySharingUser(withPermission sharingPermission:Permission, sharingUser: TestAccount = .primarySharingAccount, failureExpected:Bool = false) {
        let deviceUUID1 = Foundation.UUID().uuidString
        let sharingGroupUUID = Foundation.UUID().uuidString

        guard let _ = addNewUser(testAccount: .primaryOwningAccount, sharingGroupUUID: sharingGroupUUID, deviceUUID:deviceUUID1) else {
            XCTFail()
            return
        }
        
        // And upload a file by that user.
        guard let uploadResult = uploadTextFile(testAccount: .primaryOwningAccount, deviceUUID:deviceUUID1, addUser:.no(sharingGroupUUID: sharingGroupUUID)) else {
            XCTFail()
            return
        }
        
        sendDoneUploads(testAccount: .primaryOwningAccount, expectedNumberOfUploads: 1, deviceUUID:deviceUUID1, sharingGroupUUID: sharingGroupUUID)
        
        var sharingInvitationUUID:String!
        
        // Have that newly created user create a sharing invitation.
        createSharingInvitation(permission: sharingPermission, sharingGroupUUID:sharingGroupUUID) { expectation, invitationUUID in
            sharingInvitationUUID = invitationUUID!
            expectation.fulfill()
        }
        
        redeemSharingInvitation(sharingUser: sharingUser, sharingInvitationUUID:sharingInvitationUUID) { _, expectation in
            expectation.fulfill()
        }
        
        // Now see if we can download the file with the sharing user creds.
        downloadTextFile(testAccount: sharingUser, masterVersionExpectedWithDownload: 2, uploadFileRequest: uploadResult.request, expectedError:failureExpected)
    }
    
    func downloadDeleteFileBySharingUser(withPermission sharingPermission:Permission, sharingUser: TestAccount = .primarySharingAccount, failureExpected:Bool = false) {
    
        let deviceUUID1 = Foundation.UUID().uuidString
        let sharingGroupUUID = Foundation.UUID().uuidString

        guard let _ = addNewUser(testAccount: .primaryOwningAccount, sharingGroupUUID: sharingGroupUUID, deviceUUID:deviceUUID1) else {
            XCTFail()
            return
        }
        
        // And upload a file by that user.
        guard let uploadResult = uploadTextFile(testAccount: .primaryOwningAccount, deviceUUID:deviceUUID1, addUser:.no(sharingGroupUUID: sharingGroupUUID)) else {
            XCTFail()
            return
        }
        sendDoneUploads(testAccount: .primaryOwningAccount, expectedNumberOfUploads: 1, deviceUUID:deviceUUID1, sharingGroupUUID: sharingGroupUUID)
        
        let uploadDeletionRequest = UploadDeletionRequest(json: [
            UploadDeletionRequest.fileUUIDKey: uploadResult.request.fileUUID,
            UploadDeletionRequest.fileVersionKey: uploadResult.request.fileVersion,
            UploadDeletionRequest.masterVersionKey: uploadResult.request.masterVersion + MasterVersionInt(1),
            ServerEndpoint.sharingGroupUUIDKey: sharingGroupUUID
        ])!
        
        uploadDeletion(uploadDeletionRequest: uploadDeletionRequest, deviceUUID: deviceUUID1, addUser: false, expectError: failureExpected)
        sendDoneUploads(expectedNumberOfUploads: 1, deviceUUID:deviceUUID1, masterVersion: uploadResult.request.masterVersion + MasterVersionInt(1), sharingGroupUUID: sharingGroupUUID, failureExpected:failureExpected)
        
        var sharingInvitationUUID:String!
        
        // Have that newly created user create a sharing invitation.
        createSharingInvitation(permission: sharingPermission, sharingGroupUUID:sharingGroupUUID) { expectation, invitationUUID in
            sharingInvitationUUID = invitationUUID!
            expectation.fulfill()
        }
        
        // Redeem that sharing invitation with a new user
        redeemSharingInvitation(sharingUser: sharingUser, sharingInvitationUUID:sharingInvitationUUID) { _, expectation in
            expectation.fulfill()
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
        let result = uploadFileBySharingUser(withPermission: .read, owningAccount: .primaryOwningAccount, sharingGroupUUID: sharingGroupUUID, failureExpected:true)
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
    
    func checkFileOwner(uploadedDeviceUUID: String, owningAccount: TestAccount, ownerUserId: UserId, request: UploadFileRequest) {
        let options = CloudStorageFileNameOptions(cloudFolderName: ServerTestCase.cloudFolderName, mimeType: request.mimeType)

        let fileName = request.cloudFileName(deviceUUID:uploadedDeviceUUID, mimeType: request.mimeType)
        Log.debug("Looking for file: \(fileName)")
        guard let found = lookupFile(forOwningTestAccount: owningAccount, cloudFileName: fileName, options: options), found else {
            XCTFail()
            return
        }
    
        let key = FileIndexRepository.LookupKey.primaryKeys(sharingGroupUUID: request.sharingGroupUUID, fileUUID: request.fileUUID)
        guard case .found(let obj) = FileIndexRepository(db).lookup(key: key, modelInit: FileIndex.init), let fileIndexObj = obj as? FileIndex else {
            XCTFail()
            return
        }
        
        XCTAssert(fileIndexObj.userId == ownerUserId)
        
        // Need to make sure that the cloud storage type of the file, in the file index, corresponds to the cloud storage type of the owningAccount.
        guard let rawAccountType = fileIndexObj.accountType,
            let accountType = AccountType(rawValue: rawAccountType),
            let cloudStorageType = accountType.cloudStorageType else {
            XCTFail()
            return
        }
        
        XCTAssert(owningAccount.type.cloudStorageType == cloudStorageType)
    }

    // Check to make sure that if the invited user owns cloud storage that the file was uploaded to their cloud storage.
    func makeSureSharingOwnerOwnsUploadedFile(result: SharingUploadResult) {
        if result.sharingTestAccount.type.userType == .owning {
            checkFileOwner(uploadedDeviceUUID: result.uploadedDeviceUUID, owningAccount: result.sharingTestAccount, ownerUserId: result.redeemResponse.userId, request: result.request)
        }
    }
    
    // MARK: Write sharing user
    
    
    func testThatWriteSharingUserCanUploadAFile() {
        let sharingGroupUUID = UUID().uuidString
        
        guard let result = uploadFileBySharingUser(withPermission: .write, owningAccount: .primaryOwningAccount, sharingGroupUUID: sharingGroupUUID) else {
            XCTFail()
            return
        }
        
        makeSureSharingOwnerOwnsUploadedFile(result: result)
    }
    
    // When an owning user uploads a modified file (v1) which was initially uploaded (v0) by another owning user, that original owning user must remain the owner of the modified file.
    func testThatV0FileOwnerRemainsFileOwner() {
        // Upload v0 of file.
        let owningAccount:TestAccount = .primaryOwningAccount
        let deviceUUID = Foundation.UUID().uuidString
        guard let uploadResult = uploadTextFile(testAccount: owningAccount, deviceUUID:deviceUUID),
            let sharingGroupUUID = uploadResult.sharingGroupUUID,
            let v0UserId = uploadResult.uploadingUserId else {
            XCTFail()
            return
        }
        
        self.sendDoneUploads(expectedNumberOfUploads: 1, deviceUUID:deviceUUID, sharingGroupUUID: sharingGroupUUID)
        
        // Upload v1 of file by another user
        guard let uploadResult2 = uploadFileBySharingUser(withPermission: .write, owningAccount: owningAccount, addUser: false, sharingGroupUUID: sharingGroupUUID, fileUUID: uploadResult.request.fileUUID, fileVersion: 1, masterVersion: 1) else {
            XCTFail()
            return
        }
        
        // Check that the v0 owner still owns the file.
        checkFileOwner(uploadedDeviceUUID: uploadResult2.uploadedDeviceUUID, owningAccount: owningAccount, ownerUserId: v0UserId, request: uploadResult2.request)
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
            let sharingGroupUUID = upload1.sharingGroupUUID else {
            XCTFail()
            return
        }
        
        sendDoneUploads(expectedNumberOfUploads: 1, deviceUUID:deviceUUID, masterVersion: masterVersion, sharingGroupUUID: sharingGroupUUID)
        
        masterVersion += 1
        
        guard let upload2 = uploadFileBySharingUser(withPermission: .write, owningAccount: .primaryOwningAccount, addUser: false, sharingGroupUUID: sharingGroupUUID, masterVersion: masterVersion) else {
            XCTFail()
            return
        }

        masterVersion += 1
        
        let uploadDeletionRequest1 = UploadDeletionRequest(json: [
            UploadDeletionRequest.fileUUIDKey: upload1.request.fileUUID,
            UploadDeletionRequest.fileVersionKey: upload1.request.fileVersion,
            UploadDeletionRequest.masterVersionKey: masterVersion + 1,
            ServerEndpoint.sharingGroupUUIDKey: sharingGroupUUID
        ])!

        uploadDeletion(testAccount: upload2.sharingTestAccount, uploadDeletionRequest: uploadDeletionRequest1, deviceUUID: deviceUUID, addUser: false)

        let uploadDeletionRequest2 = UploadDeletionRequest(json: [
            UploadDeletionRequest.fileUUIDKey: upload2.request.fileUUID,
            UploadDeletionRequest.fileVersionKey: upload2.request.fileVersion,
            UploadDeletionRequest.masterVersionKey: masterVersion + 1,
            ServerEndpoint.sharingGroupUUIDKey: sharingGroupUUID
        ])!

        uploadDeletion(testAccount: upload2.sharingTestAccount, uploadDeletionRequest: uploadDeletionRequest2, deviceUUID: deviceUUID, addUser: false)

        sendDoneUploads(testAccount: upload2.sharingTestAccount, expectedNumberOfUploads: 2, deviceUUID:deviceUUID, masterVersion: masterVersion + 1, sharingGroupUUID: sharingGroupUUID)
    }
    
    // Upload deletions must go to the account of the original (v0) owning user. To test this: a) upload v0 of a file, b) have a different user upload v1 of the file. Now upload delete. Make sure the deletion works.
    func testThatUploadDeletionOfFileAfterV1UploadBySharingUserWorks() {
        // Upload v0 of file.
        let deviceUUID = Foundation.UUID().uuidString
        guard let uploadResult = uploadTextFile(deviceUUID:deviceUUID),
            let sharingGroupUUID = uploadResult.sharingGroupUUID else {
            XCTFail()
            return
        }
        
        // Upload v1 of file by another user
        self.sendDoneUploads(expectedNumberOfUploads: 1, deviceUUID:deviceUUID, sharingGroupUUID: sharingGroupUUID)
        
        var masterVersion: MasterVersionInt = 1
        
        guard let _ = uploadFileBySharingUser(withPermission: .write, owningAccount: .primaryOwningAccount, addUser: false, sharingGroupUUID: sharingGroupUUID, fileUUID: uploadResult.request.fileUUID, fileVersion: 1, masterVersion: masterVersion) else {
            XCTFail()
            return
        }
        
        masterVersion += 2
        
        let uploadDeletionRequest = UploadDeletionRequest(json: [
            UploadDeletionRequest.fileUUIDKey: uploadResult.request.fileUUID,
            UploadDeletionRequest.fileVersionKey: 1,
            UploadDeletionRequest.masterVersionKey: masterVersion,
            ServerEndpoint.sharingGroupUUIDKey: sharingGroupUUID
        ])!
        
        // Original v0 uploader deletes file.
        uploadDeletion(testAccount: .primaryOwningAccount, uploadDeletionRequest: uploadDeletionRequest, deviceUUID: deviceUUID, addUser: false)
        sendDoneUploads(testAccount: .primaryOwningAccount, expectedNumberOfUploads: 1, deviceUUID:deviceUUID, masterVersion: masterVersion, sharingGroupUUID: sharingGroupUUID)
    }
    
    // Make sure file actually gets deleted in cloud storage for non-root owning users.
    func testUploadDeletionForNonRootOwningUserWorks() {
        let sharingGroupUUID = UUID().uuidString
        guard let result = uploadFileBySharingUser(withPermission: .write, owningAccount: .primaryOwningAccount, sharingGroupUUID: sharingGroupUUID) else {
            XCTFail()
            return
        }
        
        let masterVersion: MasterVersionInt = 2
        
        let uploadDeletionRequest = UploadDeletionRequest(json: [
            UploadDeletionRequest.fileUUIDKey: result.request.fileUUID,
            UploadDeletionRequest.fileVersionKey: 0,
            UploadDeletionRequest.masterVersionKey: masterVersion,
            ServerEndpoint.sharingGroupUUIDKey: sharingGroupUUID
        ])!
        
        // Original v0 uploader deletes file.
        uploadDeletion(testAccount: result.sharingTestAccount, uploadDeletionRequest: uploadDeletionRequest, deviceUUID: result.uploadedDeviceUUID, addUser: false)
        sendDoneUploads(testAccount: result.sharingTestAccount, expectedNumberOfUploads: 1, deviceUUID:result.uploadedDeviceUUID, masterVersion: masterVersion, sharingGroupUUID: sharingGroupUUID)

        let options = CloudStorageFileNameOptions(cloudFolderName: ServerTestCase.cloudFolderName, mimeType: result.request.mimeType)
        
        // The owner of the file will be either (a) the sharing user if that user is an owning user, or (b) the inviting user otherwise.
        
        var owningUser: TestAccount!
        if result.sharingTestAccount.type.userType == .owning {
            owningUser = result.sharingTestAccount
        }
        else {
            owningUser = .primaryOwningAccount
        }

        let fileName = result.request.cloudFileName(deviceUUID:result.uploadedDeviceUUID, mimeType: result.request.mimeType)
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
        guard let result = uploadFileBySharingUser(withPermission: .admin, owningAccount: .primaryOwningAccount, sharingGroupUUID: sharingGroupUUID) else {
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
        let sharingGroupUUID = UUID().uuidString
        guard let result = uploadFileBySharingUser(withPermission: .write, owningAccount: .primaryOwningAccount, sharingUser: sharingUser, sharingGroupUUID: sharingGroupUUID) else {
            XCTFail()
            return
        }
        
        downloadTextFile(testAccount: .primaryOwningAccount, masterVersionExpectedWithDownload: 2, uploadFileRequest: result.request, expectedError:false)
    }
    
    func testThatOwningUserCanDownloadSharingUserFile() {
        owningUserCanDownloadSharingUserFile()
    }
    
    func sharingUserCanDownloadSharingUserFile(sharingUser: TestAccount = .secondarySharingAccount) {
        // uploaded by primarySharingAccount
        let sharingGroupUUID = UUID().uuidString
        guard let result = uploadFileBySharingUser(withPermission: .write, owningAccount: .primaryOwningAccount, sharingGroupUUID: sharingGroupUUID) else {
            XCTFail()
            return
        }
            
        var sharingInvitationUUID:String!
            
        createSharingInvitation(permission: .read, sharingGroupUUID: sharingGroupUUID) { expectation, invitationUUID in
            sharingInvitationUUID = invitationUUID!
            expectation.fulfill()
        }
        
        guard let masterVersion = getMasterVersion(sharingGroupUUID: sharingGroupUUID) else {
            XCTFail()
            return
        }
            
        // Redeem that sharing invitation with a new user
        redeemSharingInvitation(sharingUser: sharingUser, sharingInvitationUUID:sharingInvitationUUID) { _, expectation in
            expectation.fulfill()
        }
            
        downloadTextFile(testAccount: sharingUser, masterVersionExpectedWithDownload: Int(masterVersion + 1), uploadFileRequest: result.request, expectedError:false)
    }
    
    func testThatSharingUserCanDownloadSharingUserFile() {
        sharingUserCanDownloadSharingUserFile()
    }
    
    // After accepting a sharing invitation as an owning user (e.g., Google or Dropbox user), make sure auth tokens are stored, for that redeeming user, so that we can access cloud storage of that user.
    func testCanAccessCloudStorageOfRedeemingUser() {
        var sharingUserId: UserId!
        let sharingUser:TestAccount = .primarySharingAccount
        
        if sharingUser.type.userType == .owning {
            createSharingUser(sharingUser: sharingUser) { newUserId, _ in
                sharingUserId = newUserId
            }
            
            guard sharingUserId != nil else {
                XCTFail()
                return
            }
            
            // Reconstruct the creds of the sharing user and attempt to access their cloud storage.
            guard let cloudStorageCreds = FileController.getCreds(forUserId: sharingUserId, from: db) as? CloudStorage else {
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
    }
    
    // Add a regular user. Invite a sharing user. Delete that regular user. See what happens if the sharing user tries to upload a file.
    func testUploadByOwningSharingUserAfterInvitingUserDeletedWorks() {
        var actualSharingGroupUUID:String!
        
        // Using an owning account here as sharing user because we always want the upload to work after deleting the inviting user.
        let sharingAccount: TestAccount = .secondaryOwningAccount
        
        createSharingUser(withSharingPermission: .write, sharingUser: sharingAccount) { userId, sharingGroupUUID in
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
        guard let _ = uploadTextFile(testAccount: sharingAccount, deviceUUID:deviceUUID, addUser: .no(sharingGroupUUID:actualSharingGroupUUID), masterVersion: 1) else {
            XCTFail()
            return
        }
    }
    
    // User A invites B. B has cloud storage. B uploads. It goes to B's storage. Both A and B can download the file.
    func testUploadByOwningSharingUserThenDownloadByBothWorks() {
        let sharingAccount: TestAccount = .secondaryOwningAccount
        let sharingGroupUUID = UUID().uuidString
        guard let result = uploadFileBySharingUser(withPermission: .write, owningAccount: .primaryOwningAccount, sharingUser: sharingAccount, sharingGroupUUID: sharingGroupUUID) else {
            XCTFail()
            return
        }
        
        makeSureSharingOwnerOwnsUploadedFile(result: result)
        
        guard let masterVersion = getMasterVersion(sharingGroupUUID: sharingGroupUUID) else {
            XCTFail()
            return
        }

        guard let _ = downloadTextFile(testAccount: sharingAccount, masterVersionExpectedWithDownload: Int(masterVersion), uploadFileRequest: result.request) else {
            XCTFail()
            return
        }
        
        guard let _ = downloadTextFile(testAccount: .primaryOwningAccount, masterVersionExpectedWithDownload: Int(masterVersion), uploadFileRequest: result.request) else {
            XCTFail()
            return
        }
    }
    
    func testUploadByNonOwningSharingUserAfterInvitingUserDeletedRespondsWithGone() {
        var actualSharingGroupUUID:String!
        
        let sharingAccount: TestAccount = .nonOwningSharingAccount
        let owningUserWhenCreating:TestAccount = .primaryOwningAccount
        
        createSharingUser(withSharingPermission: .write, sharingUser: sharingAccount, owningUserWhenCreating: owningUserWhenCreating) { userId, sharingGroupUUID in
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
        let result = uploadTextFile(testAccount: sharingAccount, owningAccountType: owningUserWhenCreating.type, deviceUUID:deviceUUID, addUser: .no(sharingGroupUUID:actualSharingGroupUUID), masterVersion: 1, errorExpected: true, statusCodeExpected: HTTPStatusCode.gone)
        XCTAssert(result == nil)
    }
    
    // Similar to that above, but the non-owning, sharing user downloads a file-- that was owned by a third user, that is still on the system, and was in the same sharing group.
    func testDownloadFileOwnedByThirdUserAfterInvitingUserDeletedWorks() {
        var actualSharingGroupUUID:String!
        
        let sharingAccount1: TestAccount = .nonOwningSharingAccount
        
        // This account must be an owning account.
        let sharingAccount2: TestAccount = .secondaryOwningAccount
        
        createSharingUser(withSharingPermission: .write, sharingUser: sharingAccount1) { userId, sharingGroupUUID in
            actualSharingGroupUUID = sharingGroupUUID
        }
        
        guard var masterVersion = getMasterVersion(sharingGroupUUID: actualSharingGroupUUID) else {
            XCTFail()
            return
        }
        
        createSharingUser(withSharingPermission: .write, sharingUser: sharingAccount2, addUser: .no(sharingGroupUUID: actualSharingGroupUUID))
        
        masterVersion += 1
    
        let deviceUUID = Foundation.UUID().uuidString

        guard let uploadResult = uploadTextFile(testAccount: sharingAccount2, deviceUUID:deviceUUID, addUser: .no(sharingGroupUUID:actualSharingGroupUUID), masterVersion: masterVersion) else {
            XCTFail()
            return
        }
        
        self.sendDoneUploads(testAccount: sharingAccount2, expectedNumberOfUploads: 1, deviceUUID:deviceUUID, masterVersion: masterVersion, sharingGroupUUID: actualSharingGroupUUID)
        
        masterVersion += 1
        
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
        
        guard let _ = downloadTextFile(testAccount: sharingAccount1, masterVersionExpectedWithDownload: Int(masterVersion), uploadFileRequest: uploadResult.request) else {
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
        
        guard let masterVersion = getMasterVersion(sharingGroupUUID: sharingGroupUUID) else {
            XCTFail()
            return
        }
        
        var owningAccountType: AccountType?
        if sharingAccount.type.userType == .owning {
            owningAccountType = sharingAccount.type
        }
        else {
            owningAccountType = owningAccount.type
        }
        
        guard let _ = uploadTextFile(testAccount: sharingAccount, owningAccountType: owningAccountType, addUser: .no(sharingGroupUUID:sharingGroupUUID), masterVersion: masterVersion) else {
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
        
        guard let masterVersion = getMasterVersion(sharingGroupUUID: sharingGroupUUID) else {
            XCTFail()
            return
        }
        
        var owningAccountType: AccountType?
        if sharingAccount.type.userType == .owning {
            owningAccountType = sharingAccount.type
        }
        else {
            owningAccountType = owningAccount.type
        }
        
        let deviceUUID = Foundation.UUID().uuidString
        guard let _ = uploadTextFile(testAccount: sharingAccount, owningAccountType: owningAccountType, deviceUUID: deviceUUID, addUser: .no(sharingGroupUUID:sharingGroupUUID), masterVersion: masterVersion) else {
            XCTFail()
            return
        }
        
        sendDoneUploads(testAccount: sharingAccount, expectedNumberOfUploads: 1, deviceUUID: deviceUUID, masterVersion: masterVersion, sharingGroupUUID: sharingGroupUUID)
    }
    
    func testThatDownloadForSecondSharingGroupWorks() {
        let owningAccount: TestAccount = .primaryOwningAccount
        guard let (sharingAccount, sharingGroupUUID) = redeemWithAnExistingOtherSharingAccount() else {
            XCTFail()
            return
        }
        
        guard let masterVersion = getMasterVersion(sharingGroupUUID: sharingGroupUUID) else {
            XCTFail()
            return
        }
        
        var owningAccountType: AccountType?
        if sharingAccount.type.userType == .owning {
            owningAccountType = sharingAccount.type
        }
        else {
            owningAccountType = owningAccount.type
        }
        
        let deviceUUID = Foundation.UUID().uuidString
        guard let result = uploadTextFile(testAccount: sharingAccount, owningAccountType: owningAccountType, deviceUUID: deviceUUID, addUser: .no(sharingGroupUUID:sharingGroupUUID), masterVersion: masterVersion) else {
            XCTFail()
            return
        }
        
        sendDoneUploads(testAccount: sharingAccount, expectedNumberOfUploads: 1, deviceUUID: deviceUUID, masterVersion: masterVersion, sharingGroupUUID: sharingGroupUUID)
        
        downloadTextFile(testAccount: sharingAccount, masterVersionExpectedWithDownload: Int(masterVersion+1), uploadFileRequest: result.request)
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
            ("testUploadByNonOwningSharingUserAfterInvitingUserDeletedRespondsWithGone",
                testUploadByNonOwningSharingUserAfterInvitingUserDeletedRespondsWithGone),
            ("testDownloadFileOwnedByThirdUserAfterInvitingUserDeletedWorks",
                testDownloadFileOwnedByThirdUserAfterInvitingUserDeletedWorks),
            ("testThatUploadForSecondSharingGroupWorks", testThatUploadForSecondSharingGroupWorks),
            ("testThatDoneUploadsForSecondSharingGroupWorks", testThatDoneUploadsForSecondSharingGroupWorks),
            ("testThatDownloadForSecondSharingGroupWorks", testThatDownloadForSecondSharingGroupWorks)
        ]
    }
    
    func testLinuxTestSuiteIncludesAllTests() {
        linuxTestSuiteIncludesAllTests(testType:Sharing_FileManipulationTests.self)
    }
}

