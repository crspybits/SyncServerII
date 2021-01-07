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
        
        XCTAssert(result.response?.creationDate != nil)
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
            return uploadTextFile(uploadIndex: 1, uploadCount: 1, deviceUUID:deviceUUID, fileUUID: fileUUID, fileLabel: UUID().uuidString)
        }
    }
    
    func runUploadV0File(file: TestFile, mimeType: String?, errorExpected: Bool) {
        let deviceUUID = Foundation.UUID().uuidString
        let testAccount:TestAccount = .primaryOwningAccount
        let fileUUID = Foundation.UUID().uuidString
        
        let uploadResult = uploadServerFile(uploadIndex: 1, uploadCount: 1, testAccount:testAccount, fileLabel: UUID().uuidString, mimeType: mimeType, deviceUUID:deviceUUID, fileUUID: fileUUID, cloudFolderName: ServerTestCase.cloudFolderName, errorExpected: errorExpected, file: file)
        
        XCTAssert((uploadResult == nil) == errorExpected)
    }
    
    func testUpoadV0WithoutFileLabelFails() {
        let file:TestFile = .test1
        let deviceUUID = Foundation.UUID().uuidString
        let testAccount:TestAccount = .primaryOwningAccount
        let fileUUID = Foundation.UUID().uuidString
        
        let uploadResult = uploadServerFile(uploadIndex: 1, uploadCount: 1, testAccount:testAccount, fileLabel: nil, mimeType: file.mimeType.rawValue, deviceUUID:deviceUUID, fileUUID: fileUUID, cloudFolderName: ServerTestCase.cloudFolderName, errorExpected: true, file: file)
        
        XCTAssert(uploadResult == nil)
    }
    
    func testUploadV0FileWithoutMimeTypeFails() {
        let file:TestFile = .test1
        runUploadV0File(file: file, mimeType: nil, errorExpected: true)
    }
    
    func testUploadV0FileWithoutBadMimeTypeFails() {
        let file:TestFile = .test1
        runUploadV0File(file: file, mimeType: "foobar", errorExpected: true)
    }
    
    func testUploadV0FileWithMimeTypeWorks() {
        let file:TestFile = .test1
        runUploadV0File(file: file, mimeType: file.mimeType.rawValue, errorExpected: false)
    }
    
    func testUploadSingleV0JPEGFile() {
        uploadSingleV0File { deviceUUID, fileUUID, changeResolverName in
            return uploadJPEGFile(deviceUUID: deviceUUID, fileUUID: fileUUID)
        }
    }

    func testUploadSingleV0URLFile() {
        uploadSingleV0File { deviceUUID, fileUUID, changeResolverName in
            return uploadFileUsingServer(deviceUUID: deviceUUID, fileUUID: fileUUID, mimeType: .url, file: .testUrlFile, fileLabel: UUID().uuidString)
        }
    }
    
    func testUploadSingleV0MovFile() {
        uploadSingleV0File { deviceUUID, fileUUID, changeResolverName in
            return uploadMovFile(deviceUUID: deviceUUID, fileUUID: fileUUID)
        }
    }
    
    func testUploadSingleV0PngFile() {
        uploadSingleV0File { deviceUUID, fileUUID, changeResolverName in
            return uploadPngFile(deviceUUID: deviceUUID, fileUUID: fileUUID)
        }
    }
    
    // With non-nil changeResolverName
    let changeResolverName = CommentFile.changeResolverName
    
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
        let fileGroup = FileGroup(fileGroupUUID: Foundation.UUID().uuidString, objectType: "Foo")
        
        uploadTwoV0Files(fileUUIDs: fileUUIDs) { addUser, deviceUUID, fileUUID, uploadIndex, uploadCount in
            return uploadTextFile(uploadIndex: uploadIndex, uploadCount: uploadCount, deviceUUID:deviceUUID, fileUUID: fileUUID, addUser: addUser, fileLabel: UUID().uuidString, fileGroup: fileGroup)
        }
    }
    
    func testUploadTwoV0JPEGFiles() {
        let fileUUIDs = [Foundation.UUID().uuidString, Foundation.UUID().uuidString]
        let fileGroup = FileGroup(fileGroupUUID: Foundation.UUID().uuidString, objectType: "Foo")
        uploadTwoV0Files(fileUUIDs: fileUUIDs) { addUser, deviceUUID, fileUUID, uploadIndex, uploadCount in
            return uploadJPEGFile(uploadIndex: uploadIndex, uploadCount: uploadCount, deviceUUID: deviceUUID, fileUUID: fileUUID, addUser: addUser, fileGroup: fileGroup)
        }
    }
    
    func testUploadTwoV0URLFiles() {
        let fileUUIDs = [Foundation.UUID().uuidString, Foundation.UUID().uuidString]
        let fileGroup = FileGroup(fileGroupUUID: Foundation.UUID().uuidString, objectType: "Foobar")
        uploadTwoV0Files(fileUUIDs: fileUUIDs) { addUser, deviceUUID, fileUUID, uploadIndex, uploadCount in
            return uploadFileUsingServer(uploadIndex: uploadIndex, uploadCount: uploadCount, deviceUUID: deviceUUID, fileUUID: fileUUID, mimeType: .url, file: .testUrlFile, fileLabel: UUID().uuidString, addUser: addUser, fileGroup: fileGroup)
        }
    }
    
   func uploadTwoV0FilesWith(differentFileGroupUUIDs: Bool) {
        let fileUUIDs = [Foundation.UUID().uuidString, Foundation.UUID().uuidString]
        let deviceUUID = Foundation.UUID().uuidString
        
        var uploadIndex: Int32 = 1
        let uploadCount: Int32 = Int32(fileUUIDs.count)
        var addUser:AddUser = .yes
        let fileGroup1 = FileGroup(fileGroupUUID: Foundation.UUID().uuidString, objectType: "Foo")
        
    guard let result1 = uploadTextFile(uploadIndex: uploadIndex, uploadCount: uploadCount, deviceUUID:deviceUUID, fileUUID: fileUUIDs[Int(uploadIndex)-1], addUser: addUser, fileLabel: UUID().uuidString, fileGroup: fileGroup1),
            let sharingGroupUUID = result1.sharingGroupUUID else {
            XCTFail()
            return
        }

        addUser = .no(sharingGroupUUID: sharingGroupUUID)

        XCTAssert(result1.response?.allUploadsFinished == .uploadsNotFinished)

        let fileGroup2: FileGroup
        if differentFileGroupUUIDs {
            fileGroup2 = FileGroup(fileGroupUUID: Foundation.UUID().uuidString, objectType: "Foo")
        }
        else {
            fileGroup2 = fileGroup1
        }
        
        uploadIndex += 1
        
    let result2 = uploadTextFile(uploadIndex: uploadIndex, uploadCount: uploadCount, deviceUUID:deviceUUID, fileUUID: fileUUIDs[Int(uploadIndex)-1], addUser: addUser, fileLabel: UUID().uuidString, errorExpected: differentFileGroupUUIDs, fileGroup:fileGroup2)
        
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
        var fileGroup: FileGroup?
        
        if !nilFileGroupUUIDs {
            fileGroup = FileGroup(fileGroupUUID: Foundation.UUID().uuidString, objectType: "Foo")
        }
        
        guard let result1 = uploadTextFile(uploadIndex: uploadIndex, uploadCount: uploadCount, deviceUUID:deviceUUID, fileUUID: fileUUIDs[Int(uploadIndex)-1], addUser: addUser, fileLabel: UUID().uuidString, fileGroup: fileGroup),
            let sharingGroupUUID = result1.sharingGroupUUID else {
            XCTFail()
            return
        }

        addUser = .no(sharingGroupUUID: sharingGroupUUID)

        XCTAssert(result1.response?.allUploadsFinished == .uploadsNotFinished)
        
        uploadIndex += 1
        
        let result2 = uploadTextFile(uploadIndex: uploadIndex, uploadCount: uploadCount, deviceUUID:deviceUUID, fileUUID: fileUUIDs[Int(uploadIndex)-1], addUser: addUser, fileLabel: UUID().uuidString, errorExpected: nilFileGroupUUIDs, fileGroup:fileGroup)
        
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
        var fileGroup: FileGroup? = FileGroup(fileGroupUUID: Foundation.UUID().uuidString, objectType: "Foo")
        
        guard let result1 = uploadTextFile(uploadIndex: uploadIndex, uploadCount: uploadCount, deviceUUID:deviceUUID, fileUUID: fileUUIDs[Int(uploadIndex)-1], addUser: addUser, fileLabel: UUID().uuidString, fileGroup: fileGroup),
            let sharingGroupUUID = result1.sharingGroupUUID else {
            XCTFail()
            return
        }

        addUser = .no(sharingGroupUUID: sharingGroupUUID)

        XCTAssert(result1.response?.allUploadsFinished == .uploadsNotFinished)
        
        uploadIndex += 1
        if oneFileHasNilGroupUUID {
            fileGroup = nil
        }
        
        let result2 = uploadTextFile(uploadIndex: uploadIndex, uploadCount: uploadCount, deviceUUID:deviceUUID, fileUUID: fileUUIDs[Int(uploadIndex)-1], addUser: addUser, fileLabel: UUID().uuidString, errorExpected: oneFileHasNilGroupUUID, fileGroup:fileGroup)
        
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
    
   func testUploadFileWithJSONAppMetaDataWorks() {
        let fileUUID = Foundation.UUID().uuidString
        let deviceUUID = Foundation.UUID().uuidString
        let appMetaData = "{ \"foo\": \"bar\" }"

        guard let _ = uploadTextFile(uploadIndex: 1, uploadCount: 1, deviceUUID:deviceUUID, fileUUID: fileUUID, fileLabel: UUID().uuidString, appMetaData: appMetaData) else {
            XCTFail()
            return
        }
    }
    
    func runChangeResolverUploadTest(withValidV0: Bool) {
        let changeResolverName = CommentFile.changeResolverName
        let deviceUUID = Foundation.UUID().uuidString
        let fileUUID = Foundation.UUID().uuidString
         
        let file: TestFile
        if withValidV0 {
            file = .commentFile
        }
        else {
            file = .test1
        }
        
        let result = uploadTextFile(uploadIndex: 1, uploadCount: 1, deviceUUID:deviceUUID, fileUUID: fileUUID, fileLabel: UUID().uuidString, errorExpected:!withValidV0, stringFile: file, changeResolverName: changeResolverName)
        
        XCTAssert((result != nil) == withValidV0)
    }
    
    func testUploadV0FileWithInvalidV0ChangeResolverFails() {
        runChangeResolverUploadTest(withValidV0: false)
    }
    
    func testUploadV0FileWithValidV0ChangeResolverWorks() {
        runChangeResolverUploadTest(withValidV0: true)
    }

    func runChangeResolverUploadTest(withValidChangeResolverName: Bool) {
        let deviceUUID = Foundation.UUID().uuidString
        let fileUUID = Foundation.UUID().uuidString
        let file: TestFile = .commentFile

        let changeResolverName: String
        if withValidChangeResolverName {
            changeResolverName = CommentFile.changeResolverName
        }
        else {
            changeResolverName = "foobar"
        }
        
        let result = uploadTextFile(uploadIndex: 1, uploadCount: 1, deviceUUID:deviceUUID, fileUUID: fileUUID, fileLabel: UUID().uuidString, errorExpected:!withValidChangeResolverName, stringFile: file, changeResolverName: changeResolverName)
        
        XCTAssert((result != nil) == withValidChangeResolverName)
    }
    
    func testUploadV0FileWithInvalidChangeResolverNameFails() {
        runChangeResolverUploadTest(withValidChangeResolverName: false)
    }
    
    func testUploadV0FileWithValidChangeResolverNameWorks() {
        runChangeResolverUploadTest(withValidChangeResolverName: true)
    }
    
    func testRunV0UploadCheckSumTestWith(file: TestFile, errorExpected: Bool) {
        let deviceUUID = Foundation.UUID().uuidString
        let testAccount:TestAccount = .primaryOwningAccount
        let fileUUID = Foundation.UUID().uuidString
        
        let uploadResult = uploadServerFile(uploadIndex: 1, uploadCount: 1, testAccount:testAccount, fileLabel: UUID().uuidString, mimeType: file.mimeType.rawValue, deviceUUID:deviceUUID, fileUUID: fileUUID, cloudFolderName: ServerTestCase.cloudFolderName, errorExpected: errorExpected, file: file)
        
        XCTAssert((uploadResult == nil) == errorExpected)
    }
    
    func testUploadV0FileWithGoodCheckSumWorks() {
        testRunV0UploadCheckSumTestWith(file: .test1, errorExpected: false)
    }
    
    func testUploadV0FileWithNoCheckSumFails() {
        testRunV0UploadCheckSumTestWith(file: .testNoCheckSum, errorExpected: true)
    }
    
    func testUploadV0FileWithBadCheckSumFails() {
        testRunV0UploadCheckSumTestWith(file: .testBadCheckSum, errorExpected: true)
    }
    
    func runtestUploadWith(invalidSharingUUID: Bool) {
        guard let upload1 = uploadTextFile(uploadIndex: 1, uploadCount: 1, fileLabel: UUID().uuidString),
            let sharingGroupUUID = upload1.sharingGroupUUID else {
            XCTFail()
            return
        }
        
        let secondSharingGroupUUID: String
        if invalidSharingUUID {
            secondSharingGroupUUID = UUID().uuidString
        }
        else {
            secondSharingGroupUUID = sharingGroupUUID
        }
        
        let upload2 = uploadTextFile(uploadIndex: 1, uploadCount: 1, addUser: .no(sharingGroupUUID: secondSharingGroupUUID), fileLabel: UUID().uuidString, errorExpected: invalidSharingUUID)
        
        XCTAssert((upload2 == nil) == invalidSharingUUID)
    }
    
    func testUploadWithInvalidSharingGroupUUIDFails() {
        runtestUploadWith(invalidSharingUUID: true)
    }
    
    func testUploadWithValidSharingGroupUUIDWorks() {
        runtestUploadWith(invalidSharingUUID: false)
    }
        
    func upload(sameFileTwiceInSameBatch: Bool) {
        let fileUUID = UUID().uuidString
        let deviceUUID = UUID().uuidString

        var uploadCount:Int32 = 1
        if sameFileTwiceInSameBatch {
            uploadCount = 2
        }
        
        guard let upload1 = uploadTextFile(uploadIndex: 1, uploadCount: uploadCount, deviceUUID: deviceUUID, fileUUID: fileUUID, fileLabel: UUID().uuidString),
            let sharingGroupUUID = upload1.sharingGroupUUID else {
            XCTFail()
            return
        }

        if sameFileTwiceInSameBatch {
            guard let upload2 = uploadTextFile(uploadIndex: 2, uploadCount: uploadCount, deviceUUID: deviceUUID, fileUUID: fileUUID, addUser: .no(sharingGroupUUID: sharingGroupUUID), fileLabel: UUID().uuidString) else {
                XCTFail()
                return
            }
            
            XCTAssert(upload2.response?.allUploadsFinished == .duplicateFileUpload)
        }
    }
    
    func testUploadSameFileInBatchBySameDeviceIndicatesDuplicate() {
        upload(sameFileTwiceInSameBatch: true)
    }
}
