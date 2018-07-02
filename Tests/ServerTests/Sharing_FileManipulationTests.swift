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

class Sharing_FileManipulationTests: ServerTestCase, LinuxTestable {

    override func setUp() {
        super.setUp()
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }
    
    override func tearDown() {
        super.tearDown()
    }
    
    @discardableResult
    func uploadFileBySharingUser(withPermission sharingPermission:Permission, sharingUser: TestAccount = .primarySharingAccount, failureExpected:Bool = false) -> (request: UploadFileRequest, fileSize:Int64, SharingGroupId)? {
        let deviceUUID1 = Foundation.UUID().uuidString
        
        guard let addUserResponse = addNewUser(deviceUUID:deviceUUID1),
            let sharingGroupId = addUserResponse.sharingGroupId else {
            XCTFail()
            return nil
        }
        
        var sharingInvitationUUID:String!
        
        // Have that newly created user create a sharing invitation.
        createSharingInvitation(permission: sharingPermission, sharingGroupId:sharingGroupId) { expectation, invitationUUID in
            sharingInvitationUUID = invitationUUID!
            expectation.fulfill()
        }
        
        // Redeem that sharing invitation with a new user
        redeemSharingInvitation(sharingUser: sharingUser, sharingInvitationUUID:sharingInvitationUUID) { expectation in
            expectation.fulfill()
        }
        
        let deviceUUID2 = Foundation.UUID().uuidString
        
        // Attempting to upload a file by our sharing user
        guard let uploadResult = uploadTextFile(testAccount: sharingUser, deviceUUID:deviceUUID2, addUser: .no(sharingGroupId:sharingGroupId), errorExpected: failureExpected) else {
            XCTFail()
            return nil
        }
        
        sendDoneUploads(testAccount: sharingUser, expectedNumberOfUploads: 1, deviceUUID:deviceUUID2, sharingGroupId: sharingGroupId, failureExpected: failureExpected)
        
        return (uploadResult.request, uploadResult.fileSize, sharingGroupId)
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
        redeemSharingInvitation(sharingUser: sharingUser, sharingInvitationUUID:sharingInvitationUUID) { expectation in
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
        
        redeemSharingInvitation(sharingUser: sharingUser, sharingInvitationUUID:sharingInvitationUUID) { expectation in
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
        redeemSharingInvitation(sharingUser: sharingUser, sharingInvitationUUID:sharingInvitationUUID) { expectation in
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
    
    // MARK: Write sharing user
    func testThatWriteSharingUserCanUploadAFile() {
        guard let _ = uploadFileBySharingUser(withPermission: .write) else {
            XCTFail()
            return
        }
    }
    
    func testThatWriteSharingUserCanUploadDeleteAFile() {
        uploadDeleteFileBySharingUser(withPermission: .write)
    }
    
    func testThatWriteSharingUserCanDownloadAFile() {
        downloadFileBySharingUser(withPermission: .write)
    }
    
    func testThatWriteSharingUserCanDownloadDeleteAFile() {
        downloadDeleteFileBySharingUser(withPermission: .write)
    }
    
    // MARK: Admin sharing user
    func testThatAdminSharingUserCanUploadAFile() {
        guard let _ = uploadFileBySharingUser(withPermission: .admin) else {
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
        guard let (uploadRequest, fileSize, _) = uploadFileBySharingUser(withPermission: .write, sharingUser: sharingUser) else {
            XCTFail()
            return
        }
        
        downloadTextFile(testAccount: .primaryOwningAccount, masterVersionExpectedWithDownload: 1, uploadFileRequest: uploadRequest, fileSize: fileSize, expectedError:false)
    }
    
    func testThatOwningUserCanDownloadSharingUserFile() {
        owningUserCanDownloadSharingUserFile()
    }
    
    func sharingUserCanDownloadSharingUserFile(sharingUser: TestAccount = .secondarySharingAccount) {
        // uploaded by primarySharingAccount
        guard let (uploadRequest, fileSize, sharingGroupId) = uploadFileBySharingUser(withPermission: .write) else {
            XCTFail()
            return
        }
            
        var sharingInvitationUUID:String!
            
        createSharingInvitation(permission: .read, sharingGroupId: sharingGroupId) { expectation, invitationUUID in
            sharingInvitationUUID = invitationUUID!
            expectation.fulfill()
        }
            
        // Redeem that sharing invitation with a new user
        redeemSharingInvitation(sharingUser: sharingUser, sharingInvitationUUID:sharingInvitationUUID) { expectation in
            expectation.fulfill()
        }
            
        downloadTextFile(testAccount: sharingUser, masterVersionExpectedWithDownload: 1, uploadFileRequest: uploadRequest, fileSize: fileSize, expectedError:false)
    }
    
    func testThatSharingUserCanDownloadSharingUserFile() {
        sharingUserCanDownloadSharingUserFile()
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
            ("testThatWriteSharingUserCanUploadDeleteAFile", testThatWriteSharingUserCanUploadDeleteAFile),
            ("testThatWriteSharingUserCanDownloadAFile", testThatWriteSharingUserCanDownloadAFile),
            ("testThatWriteSharingUserCanDownloadDeleteAFile", testThatWriteSharingUserCanDownloadDeleteAFile),
            ("testThatAdminSharingUserCanUploadAFile", testThatAdminSharingUserCanUploadAFile),
            ("testThatAdminSharingUserCanUploadDeleteAFile", testThatAdminSharingUserCanUploadDeleteAFile),
            ("testThatAdminSharingUserCanDownloadAFile", testThatAdminSharingUserCanDownloadAFile),
            ("testThatAdminSharingUserCanDownloadDeleteAFile", testThatAdminSharingUserCanDownloadDeleteAFile),
            ("testThatOwningUserCanDownloadSharingUserFile", testThatOwningUserCanDownloadSharingUserFile),
            ("testThatSharingUserCanDownloadSharingUserFile", testThatSharingUserCanDownloadSharingUserFile),
        ]
    }
    
    func testLinuxTestSuiteIncludesAllTests() {
        linuxTestSuiteIncludesAllTests(testType:Sharing_FileManipulationTests.self)
    }
}

