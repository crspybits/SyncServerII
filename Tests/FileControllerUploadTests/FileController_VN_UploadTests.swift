//
//  FileController_VN_UploadTests.swift
//  Server
//
//  Created by Christopher Prince on 7/26/17.
//
//

import XCTest
@testable import Server
@testable import TestsCommon
import LoggerAPI
import HeliumLogger
import Foundation
import ServerShared
import ChangeResolvers
import Credentials

class FileController_VN_UploadTests: ServerTestCase, UploaderCommon {
    var accountManager: AccountManager!
    
    override func setUp() {
        super.setUp()
        HeliumLogger.use(.debug)
        
        accountManager = AccountManager(userRepository: UserRepository(db))
        let credentials = Credentials()
        accountManager.setupAccounts(credentials: credentials)
    }
    
    func runUploadOneV1TextFileWorks(withFileGroup: Bool) {
        let changeResolverName = CommentFile.changeResolverName
        let deviceUUID = Foundation.UUID().uuidString
        let fileUUID = Foundation.UUID().uuidString
        
        var fileGroupUUID: String?
        if withFileGroup {
            fileGroupUUID = Foundation.UUID().uuidString
        }
        
        let exampleComment = ExampleComment(messageString: "Hello, World", id: Foundation.UUID().uuidString)
         
        // First upload the v0 file.
  
        guard let result = uploadTextFile(uploadIndex: 1, uploadCount: 1, deviceUUID:deviceUUID, fileUUID: fileUUID, stringFile: .commentFile, fileGroupUUID: fileGroupUUID, changeResolverName: changeResolverName),
            let sharingGroupUUID = result.sharingGroupUUID else {
            XCTFail()
            return
        }
        
        // Next, upload v1 of the file -- i.e., upload just the specific change to the file.
        
        let fileIndex = FileIndexRepository(db)
        let upload = UploadRepository(db)
        let deferredUploads = DeferredUploadRepository(db)
        
        guard let fileIndexCount1 = fileIndex.count(),
            let uploadCount1 = upload.count(),
            let deferredUploadCount1 = deferredUploads.count() else {
            XCTFail()
            return
        }
                
        let v1ChangeData = exampleComment.updateContents
        
        guard let _ = uploadTextFile(uploadIndex: 1, uploadCount: 1, testAccount: .primaryOwningAccount, deviceUUID: deviceUUID, fileUUID: fileUUID, addUser: .no(sharingGroupUUID: sharingGroupUUID), dataToUpload: v1ChangeData) else {
            XCTFail()
            return
        }
        
        XCTAssert(fileIndexCount1 == fileIndex.count() )
        XCTAssert(uploadCount1 == upload.count())
        XCTAssert(deferredUploadCount1 == deferredUploads.count())
    }
    
    func testUploadOneV1TextFileWorks() {
        runUploadOneV1TextFileWorks(withFileGroup: true)
    }
    
    func testUploadOneV1TextFileWithNoFileGroupWorks() {
        runUploadOneV1TextFileWorks(withFileGroup: false)
    }
    
    func runUploadTwoV1TextFilesInSameSharingGroupWorks(withFileGroup: Bool) {
        let changeResolverName = CommentFile.changeResolverName
        let deviceUUID = Foundation.UUID().uuidString
        let fileUUID1 = Foundation.UUID().uuidString
        let fileUUID2 = Foundation.UUID().uuidString

        var fileGroupUUID: String?
        if withFileGroup {
            fileGroupUUID = Foundation.UUID().uuidString
        }
        
        let exampleComment1 = ExampleComment(messageString: "Hello, World", id: Foundation.UUID().uuidString)
        let exampleComment2 = ExampleComment(messageString: "Goodbye!", id: Foundation.UUID().uuidString)

        // First upload the v0 files.
  
        guard let result = uploadTextFile(uploadIndex: 1, uploadCount: 2, deviceUUID:deviceUUID, fileUUID: fileUUID1, stringFile: .commentFile, fileGroupUUID: fileGroupUUID, changeResolverName: changeResolverName),
            let sharingGroupUUID = result.sharingGroupUUID else {
            XCTFail()
            return
        }
        
        guard let _ = uploadTextFile(uploadIndex: 2, uploadCount: 2, deviceUUID:deviceUUID, fileUUID: fileUUID2, addUser: .no(sharingGroupUUID: sharingGroupUUID), stringFile: .commentFile, fileGroupUUID: fileGroupUUID, changeResolverName: changeResolverName) else {
            XCTFail()
            return
        }
        
        // Next, upload v1 of the files -- i.e., upload just the specific changes to the files.
        
        let fileIndex = FileIndexRepository(db)
        let upload = UploadRepository(db)
        let deferredUploads = DeferredUploadRepository(db)
        
        guard let fileIndexCount1 = fileIndex.count(),
            let uploadCount1 = upload.count(),
            let deferredUploadCount1 = deferredUploads.count() else {
            XCTFail()
            return
        }
                
        let v1ChangeData1 = exampleComment1.updateContents
        let v1ChangeData2 = exampleComment2.updateContents
        
        Log.debug("Starting vN uploads...")

        guard let _ = uploadTextFile(uploadIndex: 1, uploadCount: 2, testAccount: .primaryOwningAccount, deviceUUID: deviceUUID, fileUUID: fileUUID1, addUser: .no(sharingGroupUUID: sharingGroupUUID), dataToUpload: v1ChangeData1) else {
            XCTFail()
            return
        }
        
        guard let _ = uploadTextFile(uploadIndex: 2, uploadCount: 2, testAccount: .primaryOwningAccount, deviceUUID: deviceUUID, fileUUID: fileUUID2, addUser: .no(sharingGroupUUID: sharingGroupUUID), dataToUpload: v1ChangeData2) else {
            XCTFail()
            return
        }
        
        XCTAssert(fileIndexCount1 == fileIndex.count() )
        XCTAssert(uploadCount1 == upload.count())
        XCTAssert(deferredUploadCount1 == deferredUploads.count())
    }
    
    func testUploadTwoV1TextFilesInSameSharingGroupWorks() {
        runUploadTwoV1TextFilesInSameSharingGroupWorks(withFileGroup: true)
    }
    
    // Not running this without a file group -- because the test uses a file group to do a N / M batch upload.
    // func testUploadTwoV1TextFilesInDifferentSharingGroupsWorks() {
    // }
    
    // TODO: And this really is a separate set of tests than the present-- Need to work further on the plugins that are going to allow processing of the vN upload request data. They are going to take a collection of Upload rows targetting the same file, and merge the requests and update the file in cloud storage.
    
    // Deferred uploads: Where fileGroupUUID is nil
    
    // Deferred uploads: Where fileGroupUUID is non-nil

    // TODO: After that work is done, can come back here to test the results. 
    
    // TODO: Check FileIndex row specifics after each test.
    //  For change resolvers-- check for specific change resolver.
    
    // TODO: VN upload with a change resolver in vN upload.
    
    // TODO: VN upload without a change resolver in v0 upload.
    
    // TODO: VN upload with a bad change resolver name in v0 upload.
    
    // TODO: Don't allow uploading the same file twice in the same batch. This applies for v0 and vN uploads.
    
/*
    func testUploadTextAndJPEGFile() {
        let deviceUUID = Foundation.UUID().uuidString
        guard let uploadResult1 = uploadTextFile(uploadIndex: 1, uploadCount: 1, deviceUUID:deviceUUID),
            let sharingGroupUUID = uploadResult1.sharingGroupUUID else {
            XCTFail()
            return
        }
        
        XCTAssert(uploadResult1.response?.allUploadsFinished == true)
        
        guard let uploadResult2 = uploadJPEGFile(deviceUUID:deviceUUID, addUser:.no(sharingGroupUUID: sharingGroupUUID)) else {
            XCTFail()
            return
        }
        
        XCTAssert(uploadResult2.response?.allUploadsFinished == true)
    }
    
    func testUploadingSameFileTwiceWorks() {
        // index 1, count 2 so that the first upload doesn't cause a DoneUploads.
        
        let deviceUUID = Foundation.UUID().uuidString
        guard let uploadResult1 = uploadTextFile(uploadIndex: 1, uploadCount: 2, deviceUUID:deviceUUID),
            let sharingGroupUUID = uploadResult1.sharingGroupUUID else {
            XCTFail()
            return
        }

        XCTAssert(uploadResult1.response?.allUploadsFinished == false)
        
        // Second upload.
        guard let uploadResult2 = uploadTextFile(uploadIndex: 1, uploadCount: 2, deviceUUID: deviceUUID, fileUUID: uploadResult1.request.fileUUID, addUser: .no(sharingGroupUUID: sharingGroupUUID), appMetaData: uploadResult1.request.appMetaData) else {
            XCTFail()
            return
        }
        
        XCTAssert(uploadResult2.response?.allUploadsFinished == false)
    }

    func testUploadTextFileWithStringWithSpacesAppMetaData() {
        guard let _ = uploadTextFile(uploadIndex: 1, uploadCount: 1, appMetaData: "A Simple String") else {
            XCTFail()
            return
        }
    }
    
    func testUploadTextFileWithJSONAppMetaData() {
        guard let _ = uploadTextFile(uploadIndex: 1, uploadCount: 1, appMetaData: "{ \"foo\": \"bar\" }") else {
            XCTFail()
            return
        }
    }
    
    func testUploadWithInvalidMimeTypeFails() {
        let testAccount:TestAccount = .primaryOwningAccount
        let deviceUUID = Foundation.UUID().uuidString
        let sharingGroupUUID = Foundation.UUID().uuidString

        guard let _ = addNewUser(sharingGroupUUID: sharingGroupUUID, deviceUUID:deviceUUID, cloudFolderName: ServerTestCase.cloudFolderName) else {
            XCTFail()
            return
        }
        
        let fileUUIDToSend = Foundation.UUID().uuidString
        
        let file = TestFile.test1
        guard case .string(let fileContents) = file.contents,
            let data = fileContents.data(using: .utf8) else {
            XCTFail()
            return
        }

        let uploadRequest = UploadFileRequest()
        uploadRequest.fileUUID = fileUUIDToSend
        uploadRequest.mimeType = "foobar"
        uploadRequest.sharingGroupUUID = sharingGroupUUID
        uploadRequest.checkSum = file.checkSum(type: testAccount.scheme.accountName)
        
        runUploadTest(testAccount:testAccount, data:data, uploadRequest:uploadRequest, deviceUUID:deviceUUID, errorExpected: true)
    }
    
    func testUploadWithNoCheckSumFails() {
        let deviceUUID = Foundation.UUID().uuidString
        let sharingGroupUUID = Foundation.UUID().uuidString

        guard let _ = addNewUser(sharingGroupUUID: sharingGroupUUID, deviceUUID:deviceUUID, cloudFolderName: ServerTestCase.cloudFolderName) else {
            XCTFail()
            return
        }
        
        let fileUUIDToSend = Foundation.UUID().uuidString
        
        let uploadRequest = UploadFileRequest()
        uploadRequest.fileUUID = fileUUIDToSend
        uploadRequest.mimeType = "text/plain"
        uploadRequest.sharingGroupUUID = sharingGroupUUID
        
        XCTAssert(uploadRequest.valid())
    }

    func testUploadWithBadCheckSumFails() {
        let testAccount:TestAccount = .primaryOwningAccount
        let deviceUUID = Foundation.UUID().uuidString
        let sharingGroupUUID = Foundation.UUID().uuidString

        guard let _ = addNewUser(sharingGroupUUID: sharingGroupUUID, deviceUUID:deviceUUID, cloudFolderName: ServerTestCase.cloudFolderName) else {
            XCTFail()
            return
        }
        
        let fileUUIDToSend = Foundation.UUID().uuidString
        
        let file = TestFile.test1
        guard case .string(let fileContents) = file.contents,
            let data = fileContents.data(using: .utf8) else {
            XCTFail()
            return
        }

        let uploadRequest = UploadFileRequest()
        uploadRequest.fileUUID = fileUUIDToSend
        uploadRequest.mimeType = "text/plain"
        uploadRequest.sharingGroupUUID = sharingGroupUUID
        uploadRequest.checkSum = "foobar"
        
        runUploadTest(testAccount:testAccount, data:data, uploadRequest:uploadRequest, deviceUUID:deviceUUID, errorExpected: true)
    }
    
    func testUploadWithInvalidSharingGroupUUIDFails() {
        guard let _ = uploadTextFile(uploadIndex: 1, uploadCount: 1) else {
            XCTFail()
            return
        }
        
        let invalidSharingGroupUUID = UUID().uuidString
        uploadTextFile(uploadIndex: 1, uploadCount: 1, addUser: .no(sharingGroupUUID: invalidSharingGroupUUID), errorExpected: true)
    }

    func testUploadWithBadSharingGroupUUIDFails() {
        guard let _ = uploadTextFile(uploadIndex: 1, uploadCount: 1) else {
            XCTFail()
            return
        }
        
        let workingButBadSharingGroupUUID = UUID().uuidString
        guard addSharingGroup(sharingGroupUUID: workingButBadSharingGroupUUID) else {
            XCTFail()
            return
        }
        
        uploadTextFile(uploadIndex: 1, uploadCount: 1, addUser: .no(sharingGroupUUID: workingButBadSharingGroupUUID), errorExpected: true)
    }
*/
}

//extension FileController_UploadTests {
//    static var allTests : [(String, (FileController_UploadTests) -> () throws -> Void)] {
//        return [
//            ("testUploadTextFile", testUploadTextFile),
//            ("testUploadJPEGFile", testUploadJPEGFile),
//            ("testUploadURLFile", testUploadURLFile),
//            ("testUploadTextAndJPEGFile", testUploadTextAndJPEGFile),
//            ("testUploadingSameFileTwiceWorks", testUploadingSameFileTwiceWorks),
//            ("testUploadTextFileWithStringWithSpacesAppMetaData", testUploadTextFileWithStringWithSpacesAppMetaData),
//            ("testUploadTextFileWithJSONAppMetaData", testUploadTextFileWithJSONAppMetaData),
//            ("testUploadWithInvalidMimeTypeFails", testUploadWithInvalidMimeTypeFails),
//            ("testUploadWithInvalidSharingGroupUUIDFails", testUploadWithInvalidSharingGroupUUIDFails),
//            ("testUploadWithBadSharingGroupUUIDFails", testUploadWithBadSharingGroupUUIDFails)
//        ]
//    }
//
//    func testLinuxTestSuiteIncludesAllTests() {
//        linuxTestSuiteIncludesAllTests(testType:FileController_UploadTests.self)
//    }
//}
