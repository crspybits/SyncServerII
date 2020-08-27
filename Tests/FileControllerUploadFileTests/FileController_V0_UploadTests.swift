//
//  FileController_V0_UploadTests.swift
//  Server
//
//  Created by Christopher Prince on 3/22/17.
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

class FileController_V0_UploadTests: ServerTestCase {
    override func setUp() {
        super.setUp()
    }
    
    override func tearDown() {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
        super.tearDown()
    }
    
    /*
    Testing parameters:
        1) Type of file (e.g., JPEG, text, URL)
        2) Number of uploads in batch: 1, 2, ...
            Done uploads triggered?
     */
     
    // MARK: file upload, v0, 1 of 1 files.
    struct UploadResult {
        let deviceUUID: String
        let fileUUID: String
        let sharingGroupUUID: String?
    }
    
    @discardableResult
    func uploadSingleV0File(changeResolverName: String? = nil, uploadSingleFile:(_ deviceUUID: String, _ fileUUID: String, _ changeResolverName: String?)->(ServerTestCase.UploadFileResult?)) -> UploadResult? {
        let fileIndex = FileIndexRepository(db)
        let upload = UploadRepository(db)
        
        guard let fileIndexCount1 = fileIndex.count() else {
            XCTFail()
            return nil
        }
        
        guard let uploadCount1 = upload.count() else {
            XCTFail()
            return nil
        }
        
        let deviceUUID = Foundation.UUID().uuidString
        let fileUUID = Foundation.UUID().uuidString
        
        guard let result = uploadSingleFile(deviceUUID, fileUUID, changeResolverName) else {
            XCTFail()
            return nil
        }

        XCTAssert(result.response?.allUploadsFinished == .v0UploadsFinished)
                
        guard let fileIndexCount2 = fileIndex.count() else {
            XCTFail()
            return nil
        }
        
        guard let uploadCount2 = upload.count() else {
            XCTFail()
            return nil
        }
        
        // Make sure the file index has another row.
        XCTAssert(fileIndexCount1 + 1 == fileIndexCount2)
        
        // And the upload table has no more rows after.
        XCTAssert(uploadCount1 == uploadCount2)
        
        return UploadResult(deviceUUID: deviceUUID, fileUUID: fileUUID, sharingGroupUUID: result.sharingGroupUUID)
    }
    
    func testUploadSingleV0TextFile() {
        uploadSingleV0File { deviceUUID, fileUUID, changeResolverName in
            return uploadTextFile(uploadIndex: 1, uploadCount: 1, deviceUUID:deviceUUID, fileUUID: fileUUID)
        }
    }
    
    func runUploadV0File(withMimeType: Bool) {
        let file:TestFile = .test1
        let deviceUUID = Foundation.UUID().uuidString
        let testAccount:TestAccount = .primaryOwningAccount
        let fileUUID = Foundation.UUID().uuidString
        var mimeType: MimeType?
        
        if withMimeType {
            mimeType = file.mimeType
        }
        
        let uploadResult = uploadServerFile(uploadIndex: 1, uploadCount: 1, testAccount:testAccount, mimeType: mimeType, deviceUUID:deviceUUID, fileUUID: fileUUID, cloudFolderName: ServerTestCase.cloudFolderName, errorExpected: !withMimeType, file: file)
        if withMimeType {
            XCTAssert(uploadResult != nil)
        }
        else {
            XCTAssert(uploadResult == nil)
        }
    }
    
    func testUploadV0FileWithoutMimeTypeFails() {
        runUploadV0File(withMimeType: false)
    }
    
    func testUploadV0FileWithMimeTypeWorks() {
        runUploadV0File(withMimeType: true)
    }
    
    func testUploadSingleV0JPEGFile() {
        uploadSingleV0File { deviceUUID, fileUUID, changeResolverName in
            return uploadJPEGFile(deviceUUID: deviceUUID, fileUUID: fileUUID)
        }
    }

    func testUploadSingleV0URLFile() {
        uploadSingleV0File { deviceUUID, fileUUID, changeResolverName in
            return uploadFileUsingServer(deviceUUID: deviceUUID, fileUUID: fileUUID, mimeType: .url, file: .testUrlFile)
        }
    }
    
    // With non-nil changeResolverName
    let changeResolverName = CommentFile.changeResolverName
    
    func testUploadSingleV0TextFileWithChangeResolverName() {
        uploadSingleV0File(changeResolverName: changeResolverName) { deviceUUID, fileUUID, changeResolverName in
            return uploadTextFile(uploadIndex: 1, uploadCount: 1, deviceUUID:deviceUUID, fileUUID: fileUUID, changeResolverName: changeResolverName)
        }
    }
    
    func testUploadSingleV0JPEGFileWithChangeResolverName() {
        uploadSingleV0File(changeResolverName: changeResolverName) { deviceUUID, fileUUID, changeResolverName in
            return uploadJPEGFile(deviceUUID: deviceUUID, fileUUID: fileUUID, changeResolverName: changeResolverName)
        }
    }

    func testUploadSingleV0URLFileWithChangeResolverName() {
        uploadSingleV0File(changeResolverName: changeResolverName) { deviceUUID, fileUUID, changeResolverName in
            return uploadFileUsingServer(deviceUUID: deviceUUID, fileUUID: fileUUID, mimeType: .url, file: .testUrlFile, changeResolverName: changeResolverName)
        }
    }
    
    // TODO: Upload a single file, with a non-nil fileGroupUUID
    
    // MARK: file upload, v0, 1 of 2 files, and then 2 of 2 files.
    
    func uploadTwoV0Files(fileUUIDs: [String], uploadSingleFile:(_ addUser:AddUser, _ deviceUUID: String, _ fileUUID: String, _ uploadIndex: Int32, _ uploadCount: Int32)->(ServerTestCase.UploadFileResult?)) {
        let fileIndex = FileIndexRepository(db)
        let upload = UploadRepository(db)
        
        guard let fileIndexCount1 = fileIndex.count(),
            let uploadCount1 = upload.count()  else {
            XCTFail()
            return
        }
        
        let deviceUUID = Foundation.UUID().uuidString
        
        var uploadIndex: Int32 = 1
        let uploadCount: Int32 = Int32(fileUUIDs.count)
        var addUser:AddUser = .yes

        guard let result1 = uploadSingleFile(addUser, deviceUUID, fileUUIDs[Int(uploadIndex)-1], uploadIndex, uploadCount),
            let sharingGroupUUID = result1.sharingGroupUUID else {
            XCTFail()
            return
        }
        
        addUser = .no(sharingGroupUUID: sharingGroupUUID)

        XCTAssert(result1.response?.allUploadsFinished == .uploadsNotFinished)
                
        guard let fileIndexCount2 = fileIndex.count() else {
            XCTFail()
            return
        }
        
        guard let uploadCount2 = upload.count() else {
            XCTFail()
            return
        }
        
        XCTAssert(fileIndexCount1 == fileIndexCount2)
        XCTAssert(uploadCount1 + 1 == uploadCount2)
        
        uploadIndex += 1
        guard let result2 = uploadSingleFile(addUser, deviceUUID, fileUUIDs[Int(uploadIndex)-1], uploadIndex, uploadCount) else {
            XCTFail()
            return
        }

        XCTAssert(result2.response?.allUploadsFinished == .v0UploadsFinished)
                
        guard let fileIndexCount3 = fileIndex.count() else {
            XCTFail()
            return
        }
        
        guard let uploadCount3 = upload.count() else {
            XCTFail()
            return
        }
        
        XCTAssert(fileIndexCount1 + 2 == fileIndexCount3)
        XCTAssert(uploadCount3 == uploadCount1)
    }
    
    func testUploadTwoV0TextFiles() {
        let fileUUIDs = [Foundation.UUID().uuidString, Foundation.UUID().uuidString]
        let fileGroupUUID = Foundation.UUID().uuidString
        uploadTwoV0Files(fileUUIDs: fileUUIDs) { addUser, deviceUUID, fileUUID, uploadIndex, uploadCount in
            return uploadTextFile(uploadIndex: uploadIndex, uploadCount: uploadCount, deviceUUID:deviceUUID, fileUUID: fileUUID, addUser: addUser, fileGroupUUID: fileGroupUUID)
        }
    }
    
    func testUploadTwoV0JPEGFiles() {
        let fileUUIDs = [Foundation.UUID().uuidString, Foundation.UUID().uuidString]
        let fileGroupUUID = Foundation.UUID().uuidString
        uploadTwoV0Files(fileUUIDs: fileUUIDs) { addUser, deviceUUID, fileUUID, uploadIndex, uploadCount in
            return uploadJPEGFile(uploadIndex: uploadIndex, uploadCount: uploadCount, deviceUUID: deviceUUID, fileUUID: fileUUID, addUser: addUser, fileGroupUUID: fileGroupUUID)
        }
    }
    
    func testUploadTwoV0URLFiles() {
        let fileUUIDs = [Foundation.UUID().uuidString, Foundation.UUID().uuidString]
        let fileGroupUUID = Foundation.UUID().uuidString
        uploadTwoV0Files(fileUUIDs: fileUUIDs) { addUser, deviceUUID, fileUUID, uploadIndex, uploadCount in
            return uploadFileUsingServer(uploadIndex: uploadIndex, uploadCount: uploadCount, deviceUUID: deviceUUID, fileUUID: fileUUID, mimeType: .url, file: .testUrlFile, addUser: addUser, fileGroupUUID: fileGroupUUID)
        }
    }
    
   func uploadTwoV0FilesWith(differentFileGroupUUIDs: Bool) {
        let fileUUIDs = [Foundation.UUID().uuidString, Foundation.UUID().uuidString]
        let deviceUUID = Foundation.UUID().uuidString
        
        var uploadIndex: Int32 = 1
        let uploadCount: Int32 = Int32(fileUUIDs.count)
        var addUser:AddUser = .yes
        let fileGroupUUID1 = Foundation.UUID().uuidString
        
        guard let result1 = uploadTextFile(uploadIndex: uploadIndex, uploadCount: uploadCount, deviceUUID:deviceUUID, fileUUID: fileUUIDs[Int(uploadIndex)-1], addUser: addUser, fileGroupUUID: fileGroupUUID1),
            let sharingGroupUUID = result1.sharingGroupUUID else {
            XCTFail()
            return
        }

        addUser = .no(sharingGroupUUID: sharingGroupUUID)

        XCTAssert(result1.response?.allUploadsFinished == .uploadsNotFinished)

        let fileGroupUUID2: String
        if differentFileGroupUUIDs {
            fileGroupUUID2 = Foundation.UUID().uuidString
        }
        else {
            fileGroupUUID2 = fileGroupUUID1
        }
        
        uploadIndex += 1
        
        let result2 = uploadTextFile(uploadIndex: uploadIndex, uploadCount: uploadCount, deviceUUID:deviceUUID, fileUUID: fileUUIDs[Int(uploadIndex)-1], addUser: addUser, errorExpected: differentFileGroupUUIDs, fileGroupUUID:fileGroupUUID2)
        
        if differentFileGroupUUIDs {
            XCTAssert(result2 == nil)
        }
        else {
            XCTAssert(result2?.response?.allUploadsFinished == .v0UploadsFinished)
        }
    }
    
    func testUploadTwoV0FilesWithSameFileGroupUUIDsWorks() {
        uploadTwoV0FilesWith(differentFileGroupUUIDs: false)
    }
    
    func testUploadTwoV0FilesWithDifferentFileGroupUUIDsFails() {
        uploadTwoV0FilesWith(differentFileGroupUUIDs: true)
    }
    
   func uploadTwoV0FilesWith(nilFileGroupUUIDs: Bool) {
        let fileUUIDs = [Foundation.UUID().uuidString, Foundation.UUID().uuidString]
        let deviceUUID = Foundation.UUID().uuidString
        
        var uploadIndex: Int32 = 1
        let uploadCount: Int32 = Int32(fileUUIDs.count)
        var addUser:AddUser = .yes
        var fileGroupUUID: String?
        
        if !nilFileGroupUUIDs {
            fileGroupUUID = Foundation.UUID().uuidString
        }
        
        guard let result1 = uploadTextFile(uploadIndex: uploadIndex, uploadCount: uploadCount, deviceUUID:deviceUUID, fileUUID: fileUUIDs[Int(uploadIndex)-1], addUser: addUser, fileGroupUUID: fileGroupUUID),
            let sharingGroupUUID = result1.sharingGroupUUID else {
            XCTFail()
            return
        }

        addUser = .no(sharingGroupUUID: sharingGroupUUID)

        XCTAssert(result1.response?.allUploadsFinished == .uploadsNotFinished)
        
        uploadIndex += 1
        
        let result2 = uploadTextFile(uploadIndex: uploadIndex, uploadCount: uploadCount, deviceUUID:deviceUUID, fileUUID: fileUUIDs[Int(uploadIndex)-1], addUser: addUser, errorExpected: nilFileGroupUUIDs, fileGroupUUID:fileGroupUUID)
        
        if nilFileGroupUUIDs {
            XCTAssert(result2 == nil)
        }
        else {
            XCTAssert(result2?.response?.allUploadsFinished == .v0UploadsFinished)
        }
    }
    
    func testUploadTwoV0FilesWithNonNilFileGroupUUIDsWorks() {
        uploadTwoV0FilesWith(nilFileGroupUUIDs: false)
    }
    
    func testUploadTwoV0FilesWithNilFileGroupUUIDsFails() {
        uploadTwoV0FilesWith(nilFileGroupUUIDs: true)
    }
    
   func uploadTwoV0FilesWith(oneFileHasNilGroupUUID: Bool) {
        let fileUUIDs = [Foundation.UUID().uuidString, Foundation.UUID().uuidString]
        let deviceUUID = Foundation.UUID().uuidString
        
        var uploadIndex: Int32 = 1
        let uploadCount: Int32 = Int32(fileUUIDs.count)
        var addUser:AddUser = .yes
        var fileGroupUUID: String? = Foundation.UUID().uuidString
        
        guard let result1 = uploadTextFile(uploadIndex: uploadIndex, uploadCount: uploadCount, deviceUUID:deviceUUID, fileUUID: fileUUIDs[Int(uploadIndex)-1], addUser: addUser, fileGroupUUID: fileGroupUUID),
            let sharingGroupUUID = result1.sharingGroupUUID else {
            XCTFail()
            return
        }

        addUser = .no(sharingGroupUUID: sharingGroupUUID)

        XCTAssert(result1.response?.allUploadsFinished == .uploadsNotFinished)
        
        uploadIndex += 1
        if oneFileHasNilGroupUUID {
            fileGroupUUID = nil
        }
        
        let result2 = uploadTextFile(uploadIndex: uploadIndex, uploadCount: uploadCount, deviceUUID:deviceUUID, fileUUID: fileUUIDs[Int(uploadIndex)-1], addUser: addUser, errorExpected: oneFileHasNilGroupUUID, fileGroupUUID:fileGroupUUID)
        
        if oneFileHasNilGroupUUID {
            XCTAssert(result2 == nil)
        }
        else {
            XCTAssert(result2?.response?.allUploadsFinished == .v0UploadsFinished)
        }
    }
    
    func testUploadTwoV0FilesBothNonNilFileGroupUUIDsWorks() {
        uploadTwoV0FilesWith(oneFileHasNilGroupUUID: false)
    }
    
    func testUploadTwoV0FilesOneNilFileGroupUUIDsFails() {
        uploadTwoV0FilesWith(oneFileHasNilGroupUUID: true)
    }
    
    // MARK: file upload, vN, 1 of 1 files.
    
    // TODO: Try a vN upload with a change resolver. Make sure that fails.
    
    // TODO: Try a v0 upload with a bad change resolver name. Make sure it fails.
    
    func uploadSingleVNFile(changeResolverName: String? = nil, uploadSingleFile:(_ addUser:AddUser, _ deviceUUID: String, _ fileUUID: String, _ fileGroupUUID: String?, _ changeResolverName: String?)->(ServerTestCase.UploadFileResult?)) {
    
        // First upload the v0 file.
        
        var addUser:AddUser = .yes
        let fileGroupUUID = Foundation.UUID().uuidString

        let uploadResult:UploadResult! = uploadSingleV0File(changeResolverName: changeResolverName) { deviceUUID, fileUUID, changeResolverName in
            return uploadSingleFile(addUser, deviceUUID, fileUUID, fileGroupUUID, changeResolverName)
        }
        
        guard uploadResult != nil,
            let sharingGroupUUID = uploadResult.sharingGroupUUID else {
            XCTFail()
            return
        }
        
        // Next, upload v1 of the file.
        
        let fileIndex = FileIndexRepository(db)
        let upload = UploadRepository(db)
        
        guard let fileIndexCount1 = fileIndex.count() else {
            XCTFail()
            return
        }
        
        guard let uploadCount1 = upload.count() else {
            XCTFail()
            return
        }
        
        addUser = .no(sharingGroupUUID: sharingGroupUUID)
        
        guard let result = uploadSingleFile(addUser, uploadResult.deviceUUID, uploadResult.fileUUID, nil, nil) else {
            XCTFail()
            return
        }

        XCTAssert(result.response?.allUploadsFinished == .vNUploadsTransferPending)
                
        guard let fileIndexCount2 = fileIndex.count() else {
            XCTFail()
            return
        }
        
        guard let uploadCount2 = upload.count() else {
            XCTFail()
            return
        }
        
        XCTAssert(fileIndexCount1 == fileIndexCount2)
        XCTAssert(uploadCount1 + 1 == uploadCount2)
        
        // TODO: Check for additional entry in the DeferredUpload table.
    }
    
   func testUploadFileWithAppMetaDataWorks() {
        let fileUUID = Foundation.UUID().uuidString
        let deviceUUID = Foundation.UUID().uuidString
        let appMetaData = "{ \"foo\": \"bar\" }"

        guard let _ = uploadTextFile(uploadIndex: 1, uploadCount: 1, deviceUUID:deviceUUID, fileUUID: fileUUID, appMetaData: appMetaData) else {
            XCTFail()
            return
        }
    }
    
//    func testUploadOneV1TextFileWorks() {
//        uploadSingleVNFile(changeResolverName: changeResolverName) { addUser, deviceUUID, fileUUID, fileGroupUUID, changeResolverName in
//            return uploadTextFile(deviceUUID:deviceUUID, fileUUID: fileUUID, addUser: addUser, fileGroupUUID: fileGroupUUID, changeResolverName: changeResolverName)
//        }
//    }
//
//    func testUploadOneV1JPEGFileWorks() {
//        uploadSingleVNFile(changeResolverName: changeResolverName) { addUser, deviceUUID, fileUUID, fileGroupUUID, changeResolverName in
//            return uploadJPEGFile(deviceUUID: deviceUUID, fileUUID: fileUUID, addUser: addUser, fileGroupUUID: fileGroupUUID, changeResolverName: changeResolverName)
//        }
//    }
    
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
