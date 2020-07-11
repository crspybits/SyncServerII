//
//  FileController_UploadTests.swift
//  Server
//
//  Created by Christopher Prince on 3/22/17.
//
//

import XCTest
@testable import Server
@testable import TestsCommon
import LoggerAPI
import Foundation
import ServerShared

class FileController_UploadTests: ServerTestCase {
    override func setUp() {
        super.setUp()
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }
    
    override func tearDown() {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
        super.tearDown()
    }
    
//    private func lookupUpload(key: UploadRepository.LookupKey) -> Upload? {
//        let lookupResult = UploadRepository(db).lookup(key: lookupKey, modelInit: Upload.init)
//        switch lookupResult {
//        case .error, .noObjectFound:
//            return nil
//        case .found(let model):
//            guard let upload = model as? Upload else {
//                return nil
//            }
//
//            return upload
//        }
//    }
    
    /*
    Testing parameters:
        1) Type of file (e.g., JPEG, text, URL)
        2) Number of uploads in batch: 1, 2, ...
            Done uploads triggered?
        3) V0 versus later versions.
     */
     
    // MARK: file upload, v0, 1 of 1 files.

    func uploadSingleV0File(uploadSingleFile:(_ deviceUUID: String, _ fileUUID: String)->(ServerTestCase.UploadFileResult?)) {
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
        
        let deviceUUID = Foundation.UUID().uuidString
        let fileUUID = Foundation.UUID().uuidString
        
        guard let result = uploadSingleFile(deviceUUID, fileUUID) else {
            XCTFail()
            return
        }

        XCTAssert(result.response?.allUploadsFinished == .v0UploadsFinished)
                
        guard let fileIndexCount2 = fileIndex.count() else {
            XCTFail()
            return
        }
        
        guard let uploadCount2 = upload.count() else {
            XCTFail()
            return
        }
        
        // Make sure the file index has another row.
        XCTAssert(fileIndexCount1 + 1 == fileIndexCount2)
        
        // And the upload table has no more rows after.
        XCTAssert(uploadCount1 == uploadCount2)
    }
    
    func testUploadSingleV0TextFile() {
        uploadSingleV0File { deviceUUID, fileUUID in
            return uploadTextFile(uploadIndex: 1, uploadCount: 1, deviceUUID:deviceUUID, fileUUID: fileUUID)
        }
    }
    
    func testUploadSingleV0JPEGFile() {
        uploadSingleV0File { deviceUUID, fileUUID in
            return uploadJPEGFile(deviceUUID: deviceUUID, fileUUID: fileUUID)
        }
    }

    func testUploadSingleV0URLFile() {
        uploadSingleV0File { deviceUUID, fileUUID in
            return uploadFileUsingServer(deviceUUID: deviceUUID, fileUUID: fileUUID, mimeType: .url, file: .testUrlFile)
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
    
    // TODO: Check FileIndex row specifics after each test.

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
