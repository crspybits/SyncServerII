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
import PerfectLib
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
    func uploadFileBySharingUser(withPermission sharingPermission:SharingPermission, sharingUser: TestAccount = .google2, failureExpected:Bool = false) -> (request: UploadFileRequest, fileSize:Int64) {
        let deviceUUID1 = PerfectLib.UUID().string
        
        // Create a user identified by googleRefreshToken1
        addNewUser(testAccount: .google1, deviceUUID:deviceUUID1)
        
        var sharingInvitationUUID:String!
        
        // Have that newly created user create a sharing invitation.
        createSharingInvitation(permission: sharingPermission) { expectation, invitationUUID in
            sharingInvitationUUID = invitationUUID!
            expectation.fulfill()
        }
        
        // Redeem that sharing invitation with a new user: googleRefreshToken2
        redeemSharingInvitation(sharingUser: sharingUser, sharingInvitationUUID:sharingInvitationUUID) { expectation in
            expectation.fulfill()
        }
        
        let deviceUUID2 = PerfectLib.UUID().string
        
        // Attempting to upload a file by our sharing user
        let (request, fileSize) = uploadTextFile(testAccount: sharingUser, deviceUUID:deviceUUID2, addUser:false, errorExpected: failureExpected)
        
        sendDoneUploads(testAccount: sharingUser, expectedNumberOfUploads: 1, deviceUUID:deviceUUID2, failureExpected: failureExpected)
        
        return (request, fileSize)
    }
    
    func uploadDeleteFileBySharingUser(withPermission sharingPermission:SharingPermission, sharingUser: TestAccount = .google2, failureExpected:Bool = false) {
        let deviceUUID1 = PerfectLib.UUID().string
        
        // Create a user identified by googleRefreshToken1
        addNewUser(testAccount: .google1, deviceUUID:deviceUUID1)
        
        // And upload a file by that user.
        let (uploadRequest, _) = uploadTextFile(testAccount: .google1, deviceUUID:deviceUUID1, addUser:false)
        sendDoneUploads(testAccount: .google1, expectedNumberOfUploads: 1, deviceUUID:deviceUUID1)
        
        var sharingInvitationUUID:String!
        
        // Have that newly created user create a sharing invitation.
        createSharingInvitation(permission: sharingPermission) { expectation, invitationUUID in
            sharingInvitationUUID = invitationUUID!
            expectation.fulfill()
        }
        
        // Redeem that sharing invitation with a new user
        redeemSharingInvitation(sharingUser: sharingUser, sharingInvitationUUID:sharingInvitationUUID) { expectation in
            expectation.fulfill()
        }
        
        let deviceUUID2 = PerfectLib.UUID().string

        let uploadDeletionRequest = UploadDeletionRequest(json: [
            UploadDeletionRequest.fileUUIDKey: uploadRequest.fileUUID,
            UploadDeletionRequest.fileVersionKey: uploadRequest.fileVersion,
            UploadDeletionRequest.masterVersionKey: uploadRequest.masterVersion + 1
        ])!
        
        uploadDeletion(testAccount: sharingUser, uploadDeletionRequest: uploadDeletionRequest, deviceUUID: deviceUUID2, addUser: false, expectError: failureExpected)
        sendDoneUploads(testAccount: sharingUser, expectedNumberOfUploads: 1, deviceUUID:deviceUUID2, masterVersion: uploadRequest.masterVersion + 1, failureExpected:failureExpected)
    }
    
    func downloadFileBySharingUser(withPermission sharingPermission:SharingPermission, sharingUser: TestAccount = .google2, failureExpected:Bool = false) {
        let deviceUUID1 = PerfectLib.UUID().string
        
        // Create a user identified by googleRefreshToken1
        addNewUser(testAccount: .google1, deviceUUID:deviceUUID1)
        
        // And upload a file by that user.
        let (uploadRequest, fileSize) = uploadTextFile(testAccount: .google1, deviceUUID:deviceUUID1, addUser:false)
        sendDoneUploads(testAccount: .google1, expectedNumberOfUploads: 1, deviceUUID:deviceUUID1)
        
        var sharingInvitationUUID:String!
        
        // Have that newly created user create a sharing invitation.
        createSharingInvitation(permission: sharingPermission) { expectation, invitationUUID in
            sharingInvitationUUID = invitationUUID!
            expectation.fulfill()
        }
        
        redeemSharingInvitation(sharingUser: sharingUser, sharingInvitationUUID:sharingInvitationUUID) { expectation in
            expectation.fulfill()
        }
        
        // Now see if we can download the file with the sharing user creds.
        downloadTextFile(testAccount: sharingUser, masterVersionExpectedWithDownload: 1, uploadFileRequest: uploadRequest, fileSize: fileSize, expectedError:failureExpected)
    }
    
    func downloadDeleteFileBySharingUser(withPermission sharingPermission:SharingPermission, sharingUser: TestAccount = .google2, failureExpected:Bool = false) {
    
        let deviceUUID1 = PerfectLib.UUID().string
        
        // Create a user identified by googleRefreshToken1
        addNewUser(testAccount: .google1, deviceUUID:deviceUUID1)
        
        // And upload a file by that user.
        let (uploadRequest, _) = uploadTextFile(testAccount: .google1, deviceUUID:deviceUUID1, addUser:false)
        sendDoneUploads(testAccount: .google1, expectedNumberOfUploads: 1, deviceUUID:deviceUUID1)
        
        let uploadDeletionRequest = UploadDeletionRequest(json: [
            UploadDeletionRequest.fileUUIDKey: uploadRequest.fileUUID,
            UploadDeletionRequest.fileVersionKey: uploadRequest.fileVersion,
            UploadDeletionRequest.masterVersionKey: uploadRequest.masterVersion + 1
        ])!
        
        uploadDeletion(uploadDeletionRequest: uploadDeletionRequest, deviceUUID: deviceUUID1, addUser: false, expectError: failureExpected)
        sendDoneUploads(expectedNumberOfUploads: 1, deviceUUID:deviceUUID1, masterVersion: uploadRequest.masterVersion + 1, failureExpected:failureExpected)
        
        var sharingInvitationUUID:String!
        
        // Have that newly created user create a sharing invitation.
        createSharingInvitation(permission: sharingPermission) { expectation, invitationUUID in
            sharingInvitationUUID = invitationUUID!
            expectation.fulfill()
        }
        
        // Redeem that sharing invitation with a new user
        redeemSharingInvitation(sharingUser: sharingUser, sharingInvitationUUID:sharingInvitationUUID) { expectation in
            expectation.fulfill()
        }
    
        // The final step of a download deletion is to check the file index-- and make sure it's marked as deleted for us.
        
        let deviceUUID2 = PerfectLib.UUID().string

        self.performServerTest(testAccount: sharingUser) { expectation, testCreds in
            let tokenType = sharingUser.type.toAuthTokenType()
            let headers = self.setupHeaders(tokenType: tokenType, accessToken: testCreds.accessToken, deviceUUID:deviceUUID2)
            
            self.performRequest(route: ServerEndpoints.fileIndex, headers: headers, body:nil) { response, dict in
                Log.info("Status code: \(response!.statusCode)")
                XCTAssert(response!.statusCode == .OK, "Did not work on fileIndexRequest request")
                XCTAssert(dict != nil)
                
                if let fileIndexResponse = FileIndexResponse(json: dict!) {
                    XCTAssert(fileIndexResponse.fileIndex!.count == 1)
                    let fileInfo = fileIndexResponse.fileIndex![0]
                    XCTAssert(fileInfo.deleted == true)
                }
                else {
                    XCTFail()
                }
                
                expectation.fulfill()
            }
        }
    }
    
    // MARK: Read sharing user
    func testThatReadSharingGoogleUserCannotUploadAFile() {
        uploadFileBySharingUser(withPermission: .read, failureExpected:true)
    }
    
    func testThatReadSharingFacebookUserCannotUploadAFile() {
        uploadFileBySharingUser(withPermission: .read, sharingUser: .facebook1, failureExpected:true)
    }
    
    func testThatReadSharingGoogleUserCannotUploadDeleteAFile() {
        uploadDeleteFileBySharingUser(withPermission: .read, failureExpected:true)
    }
    
    func testThatReadSharingFacebookUserCannotUploadDeleteAFile() {
        uploadDeleteFileBySharingUser(withPermission: .read, sharingUser: .facebook1, failureExpected:true)
    }
    
    func testThatReadSharingGoogleUserCanDownloadAFile() {
        downloadFileBySharingUser(withPermission: .read)
    }
    
    func testThatReadSharingFacebookUserCanDownloadAFile() {
        downloadFileBySharingUser(withPermission: .read, sharingUser: .facebook1)
    }
    
    func testThatReadSharingGoogleUserCanDownloadDeleteAFile() {
        downloadDeleteFileBySharingUser(withPermission: .read)
    }
    
    func testThatReadSharingFacebookUserCanDownloadDeleteAFile() {
        downloadDeleteFileBySharingUser(withPermission: .read, sharingUser: .facebook1)
    }
    
    // MARK: Write sharing user
    func testThatWriteSharingGoogleUserCanUploadAFile() {
        uploadFileBySharingUser(withPermission: .write)
    }
    
    func testThatWriteSharingFacebookUserCanUploadAFile() {
        uploadFileBySharingUser(withPermission: .write, sharingUser: .facebook1)
    }
    
    func testThatWriteSharingGoogleUserCanUploadDeleteAFile() {
        uploadDeleteFileBySharingUser(withPermission: .write)
    }
    
    func testThatWriteSharingFacebookUserCanUploadDeleteAFile() {
        uploadDeleteFileBySharingUser(withPermission: .write, sharingUser: .facebook1)
    }
    
    func testThatWriteSharingGoogleUserCanDownloadAFile() {
        downloadFileBySharingUser(withPermission: .write)
    }
    
    func testThatWriteSharingFacebookUserCanDownloadAFile() {
        downloadFileBySharingUser(withPermission: .write, sharingUser: .facebook1)
    }
    
    func testThatWriteSharingGoogleUserCanDownloadDeleteAFile() {
        downloadDeleteFileBySharingUser(withPermission: .write)
    }
    
    func testThatWriteSharingFacebookUserCanDownloadDeleteAFile() {
        downloadDeleteFileBySharingUser(withPermission: .write, sharingUser: .facebook1)
    }
    
    // MARK: Admin sharing user
    func testThatAdminSharingGoogleUserCanUploadAFile() {
        uploadFileBySharingUser(withPermission: .admin)
    }
    
    func testThatAdminSharingFacebookUserCanUploadAFile() {
        uploadFileBySharingUser(withPermission: .admin, sharingUser: .facebook1)
    }
    
    func testThatAdminSharingGoogleUserCanUploadDeleteAFile() {
        uploadDeleteFileBySharingUser(withPermission: .admin)
    }
    
    func testThatAdminSharingFacebookUserCanUploadDeleteAFile() {
        uploadDeleteFileBySharingUser(withPermission: .admin, sharingUser: .facebook1)
    }
    
    func testThatAdminSharingGoogleUserCanDownloadAFile() {
        downloadFileBySharingUser(withPermission: .admin)
    }
    
    func testThatAdminSharingFacebookUserCanDownloadAFile() {
        downloadFileBySharingUser(withPermission: .admin, sharingUser: .facebook1)
    }
    
    func testThatAdminSharingGoogleUserCanDownloadDeleteAFile() {
        downloadDeleteFileBySharingUser(withPermission: .admin)
    }
    
    func testThatAdminSharingFacebookUserCanDownloadDeleteAFile() {
        downloadDeleteFileBySharingUser(withPermission: .admin)
    }
    
    // MARK: Across sharing and owning users.
    func owningUserCanDownloadSharingUserFile(sharingUser: TestAccount = .google2) {
        let (uploadRequest, fileSize) = uploadFileBySharingUser(withPermission: .write, sharingUser: sharingUser)
        
        downloadTextFile(testAccount: .google1, masterVersionExpectedWithDownload: 1, uploadFileRequest: uploadRequest, fileSize: fileSize, expectedError:false)
    }
    
    func testThatOwningUserCanDownloadSharingGoogleUserFile() {
        owningUserCanDownloadSharingUserFile()
    }
    
    func testThatOwningUserCanDownloadSharingFacebookUserFile() {
        owningUserCanDownloadSharingUserFile(sharingUser: .facebook1)
    }
    
    func sharingUserCanDownloadSharingUserFile(sharingUser: TestAccount = .google3) {
        let (uploadRequest, fileSize) = uploadFileBySharingUser(withPermission: .write)
            
        var sharingInvitationUUID:String!
            
        createSharingInvitation(permission: .read) { expectation, invitationUUID in
            sharingInvitationUUID = invitationUUID!
            expectation.fulfill()
        }
            
        // Redeem that sharing invitation with a new user
        redeemSharingInvitation(sharingUser: sharingUser, sharingInvitationUUID:sharingInvitationUUID) { expectation in
            expectation.fulfill()
        }
            
        downloadTextFile(testAccount: sharingUser, masterVersionExpectedWithDownload: 1, uploadFileRequest: uploadRequest, fileSize: fileSize, expectedError:false)
    }
    
    func testThatSharingUserCanDownloadSharingGoogleUserFile() {
        sharingUserCanDownloadSharingUserFile()
    }
    
    func testThatSharingUserCanDownloadSharingFacebookUserFile() {
        sharingUserCanDownloadSharingUserFile(sharingUser: .facebook1)
    }
}

extension Sharing_FileManipulationTests {
    static var allTests : [(String, (Sharing_FileManipulationTests) -> () throws -> Void)] {
        return [
            ("testThatReadSharingGoogleUserCannotUploadAFile", testThatReadSharingGoogleUserCannotUploadAFile),
            ("testThatReadSharingFacebookUserCannotUploadAFile", testThatReadSharingFacebookUserCannotUploadAFile),
            ("testThatReadSharingGoogleUserCannotUploadDeleteAFile", testThatReadSharingGoogleUserCannotUploadDeleteAFile),
            ("testThatReadSharingFacebookUserCannotUploadDeleteAFile", testThatReadSharingFacebookUserCannotUploadDeleteAFile),
            ("testThatReadSharingGoogleUserCanDownloadAFile", testThatReadSharingGoogleUserCanDownloadAFile),
            ("testThatReadSharingFacebookUserCanDownloadAFile",
             testThatReadSharingFacebookUserCanDownloadAFile),
            ("testThatReadSharingGoogleUserCanDownloadDeleteAFile", testThatReadSharingGoogleUserCanDownloadDeleteAFile),
            ("testThatReadSharingFacebookUserCanDownloadDeleteAFile", testThatReadSharingFacebookUserCanDownloadDeleteAFile),
            ("testThatWriteSharingGoogleUserCanUploadAFile", testThatWriteSharingGoogleUserCanUploadAFile),
            ("testThatWriteSharingFacebookUserCanUploadAFile", testThatWriteSharingFacebookUserCanUploadAFile),
            ("testThatWriteSharingGoogleUserCanUploadDeleteAFile", testThatWriteSharingGoogleUserCanUploadDeleteAFile),
            ("testThatWriteSharingFacebookUserCanUploadDeleteAFile", testThatWriteSharingFacebookUserCanUploadDeleteAFile),
            ("testThatWriteSharingGoogleUserCanDownloadAFile", testThatWriteSharingGoogleUserCanDownloadAFile),
            ("testThatWriteSharingFacebookUserCanDownloadAFile", testThatWriteSharingFacebookUserCanDownloadAFile),
            ("testThatWriteSharingGoogleUserCanDownloadDeleteAFile", testThatWriteSharingGoogleUserCanDownloadDeleteAFile),
            ("testThatWriteSharingFacebookUserCanDownloadDeleteAFile", testThatWriteSharingFacebookUserCanDownloadDeleteAFile),
            ("testThatAdminSharingGoogleUserCanUploadAFile", testThatAdminSharingGoogleUserCanUploadAFile),
            ("testThatAdminSharingFacebookUserCanUploadAFile", testThatAdminSharingFacebookUserCanUploadAFile),
            ("testThatAdminSharingGoogleUserCanUploadDeleteAFile", testThatAdminSharingGoogleUserCanUploadDeleteAFile),
            ("testThatAdminSharingFacebookUserCanUploadDeleteAFile", testThatAdminSharingFacebookUserCanUploadDeleteAFile),
            ("testThatAdminSharingGoogleUserCanDownloadAFile", testThatAdminSharingGoogleUserCanDownloadAFile),
            ("testThatAdminSharingFacebookUserCanDownloadAFile", testThatAdminSharingFacebookUserCanDownloadAFile),
            ("testThatAdminSharingGoogleUserCanDownloadDeleteAFile", testThatAdminSharingGoogleUserCanDownloadDeleteAFile),
            ("testThatAdminSharingFacebookUserCanDownloadDeleteAFile", testThatAdminSharingFacebookUserCanDownloadDeleteAFile),
            ("testThatOwningUserCanDownloadSharingGoogleUserFile", testThatOwningUserCanDownloadSharingGoogleUserFile),
            ("testThatOwningUserCanDownloadSharingFacebookUserFile", testThatOwningUserCanDownloadSharingFacebookUserFile),
            ("testThatSharingUserCanDownloadSharingGoogleUserFile", testThatSharingUserCanDownloadSharingGoogleUserFile),
            ("testThatSharingUserCanDownloadSharingFacebookUserFile", testThatSharingUserCanDownloadSharingFacebookUserFile),
        ]
    }
    
    func testLinuxTestSuiteIncludesAllTests() {
        linuxTestSuiteIncludesAllTests(testType:Sharing_FileManipulationTests.self)
    }
}

