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

class Sharing_FileManipulationTests: ServerTestCase {

    override func setUp() {
        super.setUp()
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }
    
    override func tearDown() {
        super.tearDown()
    }
    
    @discardableResult
    func uploadFileBySharingUser(withPermission sharingPermission:SharingPermission, failureExpected:Bool = false) -> (request: UploadFileRequest, fileSize:Int64) {
        let deviceUUID1 = PerfectLib.UUID().string
        
        // Create a user identified by googleRefreshToken1
        addNewUser(token: .googleRefreshToken1, deviceUUID:deviceUUID1)
        
        var sharingInvitationUUID:String!
        
        // Have that newly created user create a sharing invitation.
        createSharingInvitation(permission: sharingPermission) { expectation, invitationUUID in
            sharingInvitationUUID = invitationUUID!
            expectation.fulfill()
        }
        
        // Redeem that sharing invitation with a new user: googleRefreshToken2
        redeemSharingInvitation(token: .googleRefreshToken2, sharingInvitationUUID:sharingInvitationUUID) { expectation in
            expectation.fulfill()
        }
        
        let deviceUUID2 = PerfectLib.UUID().string
        
        // Attempting to upload a file by our sharing user
        let (request, fileSize) = uploadTextFile(token: .googleRefreshToken2, deviceUUID:deviceUUID2, addUser:false, errorExpected: failureExpected)
        
        sendDoneUploads(token: .googleRefreshToken2, expectedNumberOfUploads: 1, deviceUUID:deviceUUID2, failureExpected: failureExpected)
        
        return (request, fileSize)
    }
    
    func uploadDeleteFileBySharingUser(withPermission sharingPermission:SharingPermission, failureExpected:Bool = false) {
        let deviceUUID1 = PerfectLib.UUID().string
        
        // Create a user identified by googleRefreshToken1
        addNewUser(token: .googleRefreshToken1, deviceUUID:deviceUUID1)
        
        // And upload a file by that user.
        let (uploadRequest, _) = uploadTextFile(token: .googleRefreshToken1, deviceUUID:deviceUUID1, addUser:false)
        sendDoneUploads(token: .googleRefreshToken1, expectedNumberOfUploads: 1, deviceUUID:deviceUUID1)
        
        var sharingInvitationUUID:String!
        
        // Have that newly created user create a sharing invitation.
        createSharingInvitation(permission: sharingPermission) { expectation, invitationUUID in
            sharingInvitationUUID = invitationUUID!
            expectation.fulfill()
        }
        
        // Redeem that sharing invitation with a new user: googleRefreshToken2
        redeemSharingInvitation(token: .googleRefreshToken2, sharingInvitationUUID:sharingInvitationUUID) { expectation in
            expectation.fulfill()
        }
        
        let deviceUUID2 = PerfectLib.UUID().string

        let uploadDeletionRequest = UploadDeletionRequest(json: [
            UploadDeletionRequest.fileUUIDKey: uploadRequest.fileUUID,
            UploadDeletionRequest.fileVersionKey: uploadRequest.fileVersion,
            UploadDeletionRequest.masterVersionKey: uploadRequest.masterVersion + 1
        ])!
        
        uploadDeletion(token: .googleRefreshToken2, uploadDeletionRequest: uploadDeletionRequest, deviceUUID: deviceUUID2, addUser: false, expectError: failureExpected)
        sendDoneUploads(token: .googleRefreshToken2, expectedNumberOfUploads: 1, deviceUUID:deviceUUID2, masterVersion: uploadRequest.masterVersion + 1, failureExpected:failureExpected)
    }
    
    func downloadFileBySharingUser(withPermission sharingPermission:SharingPermission, failureExpected:Bool = false) {
        let deviceUUID1 = PerfectLib.UUID().string
        
        // Create a user identified by googleRefreshToken1
        addNewUser(token: .googleRefreshToken1, deviceUUID:deviceUUID1)
        
        // And upload a file by that user.
        let (uploadRequest, fileSize) = uploadTextFile(token: .googleRefreshToken1, deviceUUID:deviceUUID1, addUser:false)
        sendDoneUploads(token: .googleRefreshToken1, expectedNumberOfUploads: 1, deviceUUID:deviceUUID1)
        
        var sharingInvitationUUID:String!
        
        // Have that newly created user create a sharing invitation.
        createSharingInvitation(permission: sharingPermission) { expectation, invitationUUID in
            sharingInvitationUUID = invitationUUID!
            expectation.fulfill()
        }
        
        // Redeem that sharing invitation with a new user: googleRefreshToken2
        redeemSharingInvitation(token: .googleRefreshToken2, sharingInvitationUUID:sharingInvitationUUID) { expectation in
            expectation.fulfill()
        }
        
        // Now see if we can download the file with the sharing user creds.
        downloadTextFile(token: .googleRefreshToken2, masterVersionExpectedWithDownload: 1, uploadFileRequest: uploadRequest, fileSize: fileSize, expectedError:failureExpected)
    }
    
    func downloadDeleteFileBySharingUser(withPermission sharingPermission:SharingPermission, failureExpected:Bool = false) {
    
        let deviceUUID1 = PerfectLib.UUID().string
        
        // Create a user identified by googleRefreshToken1
        addNewUser(token: .googleRefreshToken1, deviceUUID:deviceUUID1)
        
        // And upload a file by that user.
        let (uploadRequest, _) = uploadTextFile(token: .googleRefreshToken1, deviceUUID:deviceUUID1, addUser:false)
        sendDoneUploads(token: .googleRefreshToken1, expectedNumberOfUploads: 1, deviceUUID:deviceUUID1)
        
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
        
        // Redeem that sharing invitation with a new user: googleRefreshToken2
        redeemSharingInvitation(token: .googleRefreshToken2, sharingInvitationUUID:sharingInvitationUUID) { expectation in
            expectation.fulfill()
        }
    
        // The final step of a download deletion is to check the file index-- and make sure it's marked as deleted for us.
        
        let deviceUUID2 = PerfectLib.UUID().string

        self.performServerTest(token: .googleRefreshToken2) { expectation, googleCreds in
            let headers = self.setupHeaders(accessToken: googleCreds.accessToken, deviceUUID:deviceUUID2)
            
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
    func testThatReadSharingUserCannotUploadAFile() {
        uploadFileBySharingUser(withPermission: .read, failureExpected:true)
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
        uploadFileBySharingUser(withPermission: .write)
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
        uploadFileBySharingUser(withPermission: .admin)
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
    func testThatOwningUserCanDownloadSharingUserFile() {
        let (uploadRequest, fileSize) = uploadFileBySharingUser(withPermission: .write)

        downloadTextFile(token: .googleRefreshToken1, masterVersionExpectedWithDownload: 1, uploadFileRequest: uploadRequest, fileSize: fileSize, expectedError:false)
    }
    
    func testThatSharingUserCanDownloadSharingUserFile() {
        let (uploadRequest, fileSize) = uploadFileBySharingUser(withPermission: .write)
        
        var sharingInvitationUUID:String!
        
        createSharingInvitation(permission: .read) { expectation, invitationUUID in
            sharingInvitationUUID = invitationUUID!
            expectation.fulfill()
        }
        
        // Redeem that sharing invitation with a new user
        redeemSharingInvitation(token: .googleRefreshToken3, sharingInvitationUUID:sharingInvitationUUID) { expectation in
            expectation.fulfill()
        }
        
        downloadTextFile(token: .googleRefreshToken3, masterVersionExpectedWithDownload: 1, uploadFileRequest: uploadRequest, fileSize: fileSize, expectedError:false)
    }
}
