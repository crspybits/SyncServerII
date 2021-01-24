//
//  FileDeletionTests.swift
//  ChangeResolverTests
//
//  Created by Christopher G Prince on 7/21/20.
//

import LoggerAPI
@testable import Server
@testable import TestsCommon
import KituraNet
import XCTest
import Foundation
import ServerShared
import ChangeResolvers
import Credentials
import ServerAccount

// Tests of FileDeletion

class FileDeletionTests: ServerTestCase {
    var accountManager:AccountManager!

    override func setUp() {
        super.setUp()
        accountManager = AccountManager()
        accountManager.setupAccounts(credentials: Credentials())
    }
    
    // Returns the cloud file name
    func uploadFile(file: TestFile, fileLabel: String, cloudStorage: CloudStorage, newFileUUID fileUUID: String, sharingGroupUUID: String, deviceUUID: String, testAccount: TestAccount) -> String? {
        let checkSum = file.checkSum(type: testAccount.scheme.accountName)

        let uploadRequest = UploadFileRequest()
        uploadRequest.fileUUID = fileUUID
        uploadRequest.mimeType = "text/plain"
        uploadRequest.sharingGroupUUID = sharingGroupUUID
        uploadRequest.checkSum = checkSum
        uploadRequest.fileLabel = fileLabel
    
        let options = CloudStorageFileNameOptions(cloudFolderName: ServerTestCase.cloudFolderName, mimeType: file.mimeType.rawValue)

        return uploadFile(accountType: testAccount.scheme.accountName, creds: cloudStorage, deviceUUID: deviceUUID, testFile: file, uploadRequest: uploadRequest, fileVersion: 0, options: options)
    }
    
    func testFileDeletionWithOneFile() {
        let deviceUUID = Foundation.UUID().uuidString
        let fileUUID = Foundation.UUID().uuidString
        let sharingGroupUUID = Foundation.UUID().uuidString

        guard let addUserResponse = self.addNewUser(testAccount:.primaryOwningAccount, sharingGroupUUID: sharingGroupUUID, deviceUUID:deviceUUID, cloudFolderName: ServerTestCase.cloudFolderName) else {
            XCTFail()
            return
        }
        
        guard let userId = addUserResponse.userId else {
            XCTFail()
            return
        }
        
        guard let cloudStorage = FileController.getCreds(forUserId: userId, userRepo: UserRepository(db), accountManager: accountManager, accountDelegate: nil)?.cloudStorage(mock: MockStorage()) else {
            XCTFail()
            return
        }
        
        let file: TestFile = .test1
        guard let fileName = uploadFile(file: file, fileLabel: UUID().uuidString, cloudStorage: cloudStorage, newFileUUID: fileUUID, sharingGroupUUID: sharingGroupUUID, deviceUUID: deviceUUID, testAccount: .primaryOwningAccount) else {
            XCTFail()
            return
        }
        
        let options = CloudStorageFileNameOptions(cloudFolderName: ServerTestCase.cloudFolderName, mimeType: file.mimeType.rawValue)
                    
        let fileDeletion = FileDeletion(cloudStorage: cloudStorage, cloudFileName: fileName, options: options)

        let exp1 = expectation(description: "apply")
        DispatchQueue.global().async {
            let errors = FileDeletion.apply(deletions: [fileDeletion])
            XCTAssert(errors == nil)
            exp1.fulfill()
        }
        waitExpectation(timeout: 10, handler: nil)
        
        let exp2 = expectation(description: "apply")
        cloudStorage.lookupFile(cloudFileName: fileName, options: options) { result in
            switch result {
            case .success(let found):
                XCTAssert(!found)
            default:
                XCTFail()
            }
            exp2.fulfill()
        }
        waitExpectation(timeout: 10, handler: nil)
    }

    func testFileDeletionWithTwoFiles() {
        let deviceUUID = Foundation.UUID().uuidString
        let fileUUID1 = Foundation.UUID().uuidString
        let fileUUID2 = Foundation.UUID().uuidString
        let sharingGroupUUID = Foundation.UUID().uuidString

        guard let addUserResponse = self.addNewUser(testAccount:.primaryOwningAccount, sharingGroupUUID: sharingGroupUUID, deviceUUID:deviceUUID, cloudFolderName: ServerTestCase.cloudFolderName) else {
            XCTFail()
            return
        }
        
        guard let userId = addUserResponse.userId else {
            XCTFail()
            return
        }
        
        guard let cloudStorage = FileController.getCreds(forUserId: userId, userRepo: UserRepository(db), accountManager: accountManager, accountDelegate: nil)?.cloudStorage(mock: MockStorage()) else {
            XCTFail()
            return
        }
        
        let file: TestFile = .test1
        guard let fileName1 = uploadFile(file: file, fileLabel: UUID().uuidString, cloudStorage: cloudStorage, newFileUUID: fileUUID1, sharingGroupUUID: sharingGroupUUID, deviceUUID: deviceUUID, testAccount: .primaryOwningAccount) else {
            XCTFail()
            return
        }
        
        guard let fileName2 = uploadFile(file: file, fileLabel: UUID().uuidString, cloudStorage: cloudStorage, newFileUUID: fileUUID2, sharingGroupUUID: sharingGroupUUID, deviceUUID: deviceUUID, testAccount: .primaryOwningAccount) else {
            XCTFail()
            return
        }
        
        let options = CloudStorageFileNameOptions(cloudFolderName: ServerTestCase.cloudFolderName, mimeType: file.mimeType.rawValue)
                    
        let fileDeletion1 = FileDeletion(cloudStorage: cloudStorage, cloudFileName: fileName1, options: options)
        let fileDeletion2 = FileDeletion(cloudStorage: cloudStorage, cloudFileName: fileName2, options: options)

        let exp1 = expectation(description: "apply")
        DispatchQueue.global().async {
            let errors = FileDeletion.apply(deletions: [fileDeletion1, fileDeletion2])
            XCTAssert(errors == nil)
            exp1.fulfill()
        }
        waitExpectation(timeout: 10, handler: nil)
        
        let exp2 = expectation(description: "apply")
        cloudStorage.lookupFile(cloudFileName: fileName1, options: options) { result in
            switch result {
            case .success(let found):
                XCTAssert(!found)
            default:
                XCTFail()
            }
            exp2.fulfill()
        }
        waitExpectation(timeout: 10, handler: nil)
        
        let exp3 = expectation(description: "apply")
        cloudStorage.lookupFile(cloudFileName: fileName2, options: options) { result in
            switch result {
            case .success(let found):
                XCTAssert(!found)
            default:
                XCTFail()
            }
            exp3.fulfill()
        }
        waitExpectation(timeout: 10, handler: nil)
    }
        
    func testFileDeletionWithOneFileAndOneFailure() {
        let deviceUUID = Foundation.UUID().uuidString
        let fileUUID1 = Foundation.UUID().uuidString
        let fileUUID2 = Foundation.UUID().uuidString // not uploaded
        let sharingGroupUUID = Foundation.UUID().uuidString

        guard let addUserResponse = self.addNewUser(testAccount:.primaryOwningAccount, sharingGroupUUID: sharingGroupUUID, deviceUUID:deviceUUID, cloudFolderName: ServerTestCase.cloudFolderName) else {
            XCTFail()
            return
        }
        
        guard let userId = addUserResponse.userId else {
            XCTFail()
            return
        }
        
        guard let cloudStorage = FileController.getCreds(forUserId: userId, userRepo: UserRepository(db), accountManager: accountManager, accountDelegate: nil)?.cloudStorage(mock: MockStorage()) else {
            XCTFail()
            return
        }
        
        let file: TestFile = .test1
        guard let fileName1 = uploadFile(file: file, fileLabel: UUID().uuidString, cloudStorage: cloudStorage, newFileUUID: fileUUID1, sharingGroupUUID: sharingGroupUUID, deviceUUID: deviceUUID, testAccount: .primaryOwningAccount) else {
            XCTFail()
            return
        }
        
        let options = CloudStorageFileNameOptions(cloudFolderName: ServerTestCase.cloudFolderName, mimeType: file.mimeType.rawValue)
                    
        let fileDeletion1 = FileDeletion(cloudStorage: cloudStorage, cloudFileName: fileName1, options: options)
        let fileDeletion2 = FileDeletion(cloudStorage: cloudStorage, cloudFileName: fileUUID2, options: options)

        let exp1 = expectation(description: "apply")
        
        // Put the bad file deletion first-- so we can show that the deletion continues on a failure.
        DispatchQueue.global().async {
            let errors = FileDeletion.apply(deletions: [fileDeletion2, fileDeletion1])
            XCTAssert(errors != nil, "\(String(describing: errors))")
            XCTAssert(errors?.count == 1)
            exp1.fulfill()
        }
        waitExpectation(timeout: 10, handler: nil)
        
        let exp2 = expectation(description: "apply")
        cloudStorage.lookupFile(cloudFileName: fileName1, options: options) { result in
            switch result {
            case .success(let found):
                XCTAssert(!found)
            default:
                XCTFail()
            }
            exp2.fulfill()
        }
        waitExpectation(timeout: 10, handler: nil)
    }
}
