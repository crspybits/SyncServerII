//
//  SharingAccountsController_CreateSharingInvitation.swift
//  Server
//
//  Created by Christopher Prince on 4/11/17.
//
//

import XCTest
@testable import Server
import LoggerAPI
import PerfectLib
import Foundation

class SharingAccountsController_CreateSharingInvitation: ServerTestCase {

    override func setUp() {
        super.setUp()
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }

    override func tearDown() {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
        super.tearDown()
    }

    func createSharingInvitation(permission: SharingPermission? = nil, deviceUUID:String = PerfectLib.UUID().string, completion:@escaping (_ sharingInvitationUUID:String?)->()) {
        self.performServerTest { expectation, googleCreds in
            let headers = self.setupHeaders(accessToken: googleCreds.accessToken, deviceUUID:deviceUUID)
            
            var request:CreateSharingInvitationRequest!
            if permission == nil {
                request = CreateSharingInvitationRequest(json: [:])
            }
            else {
                request = CreateSharingInvitationRequest(json: [
                    CreateSharingInvitationRequest.sharingPermissionKey : permission!
                ])
            }
            
            self.performRequest(route: ServerEndpoints.createSharingInvitation, headers: headers, urlParameters: "?" + request!.urlParameters()!, body:nil) { response, dict in
                Log.info("Status code: \(response!.statusCode)")
                if permission == nil {
                    XCTAssert(response!.statusCode != .OK)
                    completion(nil)
                }
                else {
                    XCTAssert(response!.statusCode == .OK, "Did not work on request")
                    XCTAssert(dict != nil)
                    let response = CreateSharingInvitationResponse(json: dict!)
                    completion(response?.sharingInvitationUUID)
                }
                
                expectation.fulfill()
            }
        }
    }
    
    func testSuccessfulReadSharingInvitationCreationForOwningUser() {
        let deviceUUID = PerfectLib.UUID().string
        self.addNewUser(deviceUUID:deviceUUID)
        self.createSharingInvitation(permission: .read) { invitationUUID in
            XCTAssert(invitationUUID != nil)
            guard let _ = UUID(uuidString: invitationUUID!) else {
                XCTFail()
                return
            }
        }
    }
    
    func testSuccessfulWriteSharingInvitationCreationForOwningUser() {
        let deviceUUID = PerfectLib.UUID().string
        self.addNewUser(deviceUUID:deviceUUID)
        self.createSharingInvitation(permission: .write) { invitationUUID in
            XCTAssert(invitationUUID != nil)
            guard let _ = UUID(uuidString: invitationUUID!) else {
                XCTFail()
                return
            }
        }
    }

    // TODO: *0*
    func testSuccessfulSharingInvitationCreationForAdminSharingUser() {
        // Todo this, the current user needs to be an admin sharing user. Thus, I have to be able to create an admin sharing user. This amounts to being able to redeem a sharing invitation. Thus, I need the redeem sharing invitation endpoint to do this test.
    }
    
    // TODO: *0*
    func testFailureOfSharingInvitationCreationForReadSharingUser() {
    }
    
    // TODO: *0*
    func testFailureOfSharingInvitationCreationForWriteSharingUser() {
    }
    
    func testSharingInvitationCreationFailsWithNoAuthorization() {
        self.performServerTest { expectation, googleCreds in
            let request = CreateSharingInvitationRequest(json: [
                CreateSharingInvitationRequest.sharingPermissionKey : SharingPermission.read
            ])
            
            self.performRequest(route: ServerEndpoints.createSharingInvitation, urlParameters: "?" + request!.urlParameters()!, body:nil) { response, dict in
                Log.info("Status code: \(response!.statusCode)")
                XCTAssert(response!.statusCode != .OK, "Worked with bad request!")
                expectation.fulfill()
            }
        }
    }
}
