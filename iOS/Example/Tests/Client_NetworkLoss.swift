//
//  Client_NetworkLoss.swift
//  SyncServer
//
//  Created by Christopher Prince on 2/27/17.
//  Copyright © 2017 Spastic Muffin, LLC. All rights reserved.
//

import XCTest
@testable import SyncServer
import SMCoreLib

class ServerAPI_NetworkLoss: TestCase {
    
    override func setUp() {
        super.setUp()
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }
    
    override func tearDown() {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
        super.tearDown()
        Network.session().debugNetworkOff = false
    }
    
    func apiCallNetworkLoss(networkLoss:Bool=true, runTest:(XCTestExpectation)->()) {
        if networkLoss {
            Network.session().debugNetworkOff = true
        }
        
        let expectation = self.expectation(description: "expectation")
        runTest(expectation)
        waitForExpectations(timeout: 40.0, handler: nil)
    }
    
    // TODO: *3* These tests could be improved. I'm not actually assessing that they retry 3x
    
    func testHealthCheckNetworkLoss() {
        apiCallNetworkLoss() { exp in
            ServerAPI.session.healthCheck { error in
                XCTAssert(error != nil)
                exp.fulfill()
            }
        }
    }
    
    func testAddUserNetworkLoss() {
        apiCallNetworkLoss() { exp in
            ServerAPI.session.addUser { error in
                XCTAssert(error != nil)
                exp.fulfill()
            }
        }
    }
    
    func testCheckCredsNetworkLoss() {
        apiCallNetworkLoss() { exp in
            ServerAPI.session.checkCreds() { (userExists, error) in
                XCTAssert(error != nil)
                exp.fulfill()
            }
        }
    }
    
    func testRemoveUserNetworkLoss() {
        apiCallNetworkLoss() { exp in
            ServerAPI.session.removeUser() { error in
                XCTAssert(error != nil)
                exp.fulfill()
            }
        }
    }
    
    func testFileIndexNetworkLoss() {
        apiCallNetworkLoss() { exp in
            ServerAPI.session.fileIndex() { (fileIndex, masterVersion, error) in
                XCTAssert(error != nil)
                exp.fulfill()
            }
        }
    }
    
    func testUploadFileNetworkLoss() {
        let uploadFileUUID = UUID().uuidString

        let fileURL = Bundle(for: ServerAPI_UploadFile.self).url(forResource: "UploadMe", withExtension: "txt")!
        
        let file = ServerAPI.File(localURL: fileURL, fileUUID: uploadFileUUID, mimeType: "text/plain", cloudFolderName: cloudFolderName, deviceUUID: deviceUUID.uuidString, appMetaData: nil, fileVersion: 0, creationDate:Date(), updateDate:Date())
        
        let masterVersion = getMasterVersion()

        apiCallNetworkLoss() { exp in
            ServerAPI.session.uploadFile(file: file, serverMasterVersion: masterVersion) { (result, error) in
                XCTAssert(error != nil)
                exp.fulfill()
            }
        }
    }
    
    func testDoneUploadsNetworkLoss() {
        let masterVersion = getMasterVersion()

        apiCallNetworkLoss() { exp in
            ServerAPI.session.doneUploads(serverMasterVersion: masterVersion) { (result, error) in
                XCTAssert(error != nil)
                exp.fulfill()
            }
        }
    }
    
    func testDownloadFileNetworkLoss() {
        let masterVersion = getMasterVersion()

        let fileUUID = UUID().uuidString
        let fileURL = Bundle(for: ServerAPI_UploadFile.self).url(forResource: "UploadMe", withExtension: "txt")!
        
        guard let (_, _) = uploadFile(fileURL:fileURL, mimeType: "text/plain", fileUUID: fileUUID, serverMasterVersion: masterVersion) else {
            return
        }
        
        doneUploads(masterVersion: masterVersion, expectedNumberUploads: 1)
        
        let downloadFile = FilenamingObject(fileUUID: fileUUID, fileVersion: 0)
    
        apiCallNetworkLoss() { exp in
            ServerAPI.session.downloadFile(file: downloadFile, serverMasterVersion: masterVersion + 1) { (result, error) in
                XCTAssert(error != nil)
                exp.fulfill()
            }
        }
    }
    
    func testUploadDeletionNetworkLoss() {
        let masterVersion = getMasterVersion()

        let fileUUID = UUID().uuidString
        let fileURL = Bundle(for: ServerAPI_UploadFile.self).url(forResource: "UploadMe", withExtension: "txt")!
        
        guard let (_, _) = uploadFile(fileURL:fileURL, mimeType: "text/plain", fileUUID: fileUUID, serverMasterVersion: masterVersion) else {
            return
        }
        
        doneUploads(masterVersion: masterVersion, expectedNumberUploads: 1)
        
        let fileToDelete = ServerAPI.FileToDelete(fileUUID: fileUUID, fileVersion: 0)
        
        apiCallNetworkLoss() { exp in
            ServerAPI.session.uploadDeletion(file: fileToDelete, serverMasterVersion: 0) { (result, error) in
                XCTAssert(error != nil)
                exp.fulfill()
            }
        }
    }
}
