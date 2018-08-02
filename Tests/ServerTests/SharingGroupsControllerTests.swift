//
//  SharingGroupsControllerTests.swift
//  ServerTests
//
//  Created by Christopher G Prince on 7/15/18.
//

import XCTest
@testable import Server
import LoggerAPI
import Foundation
import SyncServerShared

class SharingGroupsControllerTests: ServerTestCase, LinuxTestable {
    override func setUp() {
        super.setUp()
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }
    
    override func tearDown() {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
        super.tearDown()
    }
    
    func getSharingGroup(testAccount:TestAccount = .primaryOwningAccount, deviceUUID:String) -> GetSharingGroupsResponse? {
        var result:GetSharingGroupsResponse?
        
        let getSharingGroupsRequest = GetSharingGroupsRequest(json: [:])!
        
        self.performServerTest(testAccount:testAccount) { expectation, creds in
            let headers = self.setupHeaders(testUser: testAccount, accessToken: creds.accessToken, deviceUUID:deviceUUID)
            
            var queryParams:String?
            if let params = getSharingGroupsRequest.urlParameters() {
                queryParams = "?" + params
            }
            
            self.performRequest(route: ServerEndpoints.getSharingGroups, headers: headers, urlParameters: queryParams) { response, dict in
                Log.info("Status code: \(response!.statusCode)")
                XCTAssert(response!.statusCode == .OK, "Did not work on getSharingGroups request: \(response!.statusCode)")
                if let dict = dict, let getSharingGroupsResponse = GetSharingGroupsResponse(json: dict) {
                    XCTAssert(getSharingGroupsResponse.sharingGroups != nil)
                    result = getSharingGroupsResponse
                }
                else {
                    XCTFail()
                }

                expectation.fulfill()
            }
        }
        
        return result
    }

    func testGetSharingGroups() {
        let deviceUUID = Foundation.UUID().uuidString
        
        guard let addUserResponse = addNewUser(deviceUUID:deviceUUID),
            let sharingGroupId = addUserResponse.sharingGroupId else {
            XCTFail()
            return
        }
        
        guard let getSharingGroupsResponse = getSharingGroup(deviceUUID:deviceUUID),
            let sharingGroups = getSharingGroupsResponse.sharingGroups,
            sharingGroups.count == 1 else {
            XCTFail()
            return
        }
        
        XCTAssert(sharingGroups[0].sharingGroupId == sharingGroupId)
    }
    
    func testCreateSharingGroupWorks() {
    
    }
}

extension SharingGroupsControllerTests {
    static var allTests : [(String, (SharingGroupsControllerTests) -> () throws -> Void)] {
        return [
            ("testGetSharingGroups", testGetSharingGroups),
            ("testCreateSharingGroupWorks", testCreateSharingGroupWorks)
        ]
    }
    
    func testLinuxTestSuiteIncludesAllTests() {
        linuxTestSuiteIncludesAllTests(testType: SharingGroupsControllerTests.self)
    }
}
