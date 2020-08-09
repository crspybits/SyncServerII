//
//  FileControllerTests.swift
//  Server
//
//  Created by Christopher Prince on 1/15/17.
//
//

import XCTest
@testable import Server
@testable import TestsCommon
import LoggerAPI
import Foundation
import ServerShared
import ServerAccount

class FileControllerTests: ServerTestCase {

    override func setUp() {
        super.setUp()
    }
    
    override func tearDown() {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
        super.tearDown()
    }

    func testIndexWithNoFiles() {
        let deviceUUID = Foundation.UUID().uuidString
        let sharingGroupUUID = Foundation.UUID().uuidString

        guard let _ = self.addNewUser(sharingGroupUUID: sharingGroupUUID, deviceUUID:deviceUUID) else {
            XCTFail()
            return
        }
        
        self.getIndex(expectedFiles: [], sharingGroupUUID: sharingGroupUUID)
    }
    
    func testGetIndexForOnlySharingGroupsWorks() {
        let deviceUUID = Foundation.UUID().uuidString
        let sharingGroupUUID = Foundation.UUID().uuidString

        guard let _ = addNewUser(sharingGroupUUID: sharingGroupUUID, deviceUUID:deviceUUID) else {
            XCTFail()
            return
        }
        
        guard let (files, sharingGroups) = getIndex() else {
            XCTFail()
            return
        }
        
        XCTAssert(files == nil)
        
        guard sharingGroups.count == 1 else {
            XCTFail()
            return
        }
        
        XCTAssert(sharingGroups[0].sharingGroupUUID == sharingGroupUUID)
        XCTAssert(sharingGroups[0].sharingGroupName == nil)
        XCTAssert(sharingGroups[0].deleted == false)
        guard sharingGroups[0].sharingGroupUsers != nil, sharingGroups[0].sharingGroupUsers.count == 1 else {
            XCTFail()
            return
        }
        
        sharingGroups[0].sharingGroupUsers.forEach { sgu in
            XCTAssert(sgu.name != nil)
            XCTAssert(sgu.userId != nil)
        }
    }
    
    func testIndexWithOneFile() {
        let deviceUUID = Foundation.UUID().uuidString
        let testAccount:TestAccount = .primaryOwningAccount
        
        guard let uploadResult = uploadTextFile(testAccount: testAccount, deviceUUID:deviceUUID),
            let sharingGroupUUID = uploadResult.sharingGroupUUID else {
            XCTFail()
            return
        }
        
        // Have to do a DoneUploads to transfer the files into the FileIndex
        //self.sendDoneUploads(expectedNumberOfUploads: 1, deviceUUID:deviceUUID, sharingGroupUUID: sharingGroupUUID)
        
        let key = FileIndexRepository.LookupKey.primaryKeys(sharingGroupUUID: sharingGroupUUID, fileUUID: uploadResult.request.fileUUID)
        
        let fileIndexResult = FileIndexRepository(db).lookup(key: key, modelInit: FileIndex.init)
        guard case .found(let obj) = fileIndexResult,
            let fileIndexObj = obj as? FileIndex else {
            XCTFail()
            return
        }
        
        guard fileIndexObj.lastUploadedCheckSum != nil else {
            XCTFail()
            return
        }
        
        self.getIndex(expectedFiles: [uploadResult.request], sharingGroupUUID: sharingGroupUUID)
        
        guard let (files, sharingGroups) = getIndex(sharingGroupUUID: sharingGroupUUID),
            let theFiles = files else {
            XCTFail()
            return
        }
        
        XCTAssert(files != nil)
        
        guard sharingGroups.count == 1, sharingGroups[0].sharingGroupUUID == sharingGroupUUID,  sharingGroups[0].sharingGroupName == nil,
            sharingGroups[0].deleted == false
            else {
            XCTFail()
            return
        }
        
        for file in theFiles {
            guard let cloudStorageType = file.cloudStorageType else {
                XCTFail()
                return
            }
            
            if file.fileUUID == uploadResult.request.fileUUID {
                XCTAssert(testAccount.scheme.cloudStorageType == cloudStorageType)
            }
        }
    }
    
    func testIndexWithTwoFiles() {
        let deviceUUID = Foundation.UUID().uuidString
        guard let uploadResult1 = uploadTextFile(deviceUUID:deviceUUID),
            let sharingGroupUUID = uploadResult1.sharingGroupUUID else {
            XCTFail()
            return
        }
        
        guard let uploadResult2 = uploadJPEGFile(deviceUUID:deviceUUID, addUser:.no(sharingGroupUUID: sharingGroupUUID)) else {
            XCTFail()
            return
        }
        
        // Have to do a DoneUploads to transfer the files into the FileIndex
        //self.sendDoneUploads(expectedNumberOfUploads: 2, deviceUUID:deviceUUID, sharingGroupUUID: sharingGroupUUID)
        
        self.getIndex(expectedFiles: [uploadResult1.request, uploadResult2.request], sharingGroupUUID: sharingGroupUUID)
    }
    
    func testIndexWithFakeSharingGroupUUIDFails() {
        let deviceUUID = Foundation.UUID().uuidString
        guard let uploadResult = uploadTextFile(uploadIndex: 1, uploadCount: 1, deviceUUID:deviceUUID), let sharingGroupUUID = uploadResult.sharingGroupUUID else {
            XCTFail()
            return
        }
        
        // Have to do a DoneUploads to transfer the files into the FileIndex
        //self.sendDoneUploads(expectedNumberOfUploads: 1, deviceUUID:deviceUUID, sharingGroupUUID: sharingGroupUUID)
        
        let invalidSharingGroupUUID = UUID().uuidString
        
        self.getIndex(expectedFiles: [uploadResult.request], sharingGroupUUID: invalidSharingGroupUUID, errorExpected: true)
    }
    
    func testIndexWithBadSharingGroupUUIDFails() {
        let deviceUUID = Foundation.UUID().uuidString
        guard let uploadResult = uploadTextFile(uploadIndex: 1, uploadCount: 1, deviceUUID:deviceUUID),
            let sharingGroupUUID = uploadResult.sharingGroupUUID else {
            XCTFail()
            return
        }
        
        // Have to do a DoneUploads to transfer the files into the FileIndex
        //self.sendDoneUploads(expectedNumberOfUploads: 1, deviceUUID:deviceUUID, sharingGroupUUID: sharingGroupUUID)
        
        let workingButBadSharingGroupUUID = UUID().uuidString
        guard addSharingGroup(sharingGroupUUID: workingButBadSharingGroupUUID) else {
            XCTFail()
            return
        }
        
        self.getIndex(expectedFiles: [uploadResult.request], sharingGroupUUID: workingButBadSharingGroupUUID, errorExpected: true)
    }
    
    // TODO: *0*: Make sure we're not trying to download a file that has already been deleted.
    
    // TODO: *1* Make sure its an error for a different user to download our file even if they have the fileUUID and fileVersion.
    
    // TODO: *1* Test that two concurrent downloads work.
}


