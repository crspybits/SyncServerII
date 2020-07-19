
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

class ApplyDeferredUploadsTests: ServerTestCase {
    /*
    func testBoostrapInputFile() throws {
        let commentFile = CommentFile()
        let data = try commentFile.getData()
        
        guard let string = String(data: data, encoding: .utf8) else {
            XCTFail()
            return
        }
        
        Log.debug("string: \(string)")
    }
    */
    
    func doAddUpload(sharingGroupUUID: String, checkSum: String? = "", uploadContents: Data? = nil, changeResolverName: String = "ExampleChangeResolver", uploadIndex: Int32 = 1, uploadCount: Int32 = 1, mimeType:String? = "text/plain", appMetaData:AppMetaData? = AppMetaData(version: 0, contents: "{ \"foo\": \"bar\" }"), userId:UserId = 1, deviceUUID:String = Foundation.UUID().uuidString, deferredUploadId: Int64? = nil, missingField:Bool = false) -> Upload {
        let upload = Upload()
        
        if !missingField {
            upload.deviceUUID = deviceUUID
        }
        
        upload.lastUploadedCheckSum = checkSum
        upload.fileUUID = Foundation.UUID().uuidString
        upload.fileVersion = 13
        upload.mimeType = mimeType
        upload.state = .uploadingFile
        upload.userId = userId
        upload.appMetaData = appMetaData?.contents
        upload.appMetaDataVersion = appMetaData?.version
        upload.creationDate = Date()
        upload.updateDate = Date()
        upload.sharingGroupUUID = sharingGroupUUID
        upload.uploadContents = uploadContents
        upload.uploadCount = uploadCount
        upload.uploadIndex = uploadIndex
        upload.deferredUploadId = deferredUploadId
        upload.changeResolverName = changeResolverName
        
        let result = UploadRepository(db).add(upload: upload)
        
        var uploadId:Int64?
        switch result {
        case .success(uploadId: let id):
            if missingField {
                XCTFail()
            }
            uploadId = id
        
        default:
            if !missingField {
                XCTFail()
            }
        }
        
        upload.uploadId = uploadId
        
        return upload
    }
    
    // Returns the cloud file name
    func uploadFile(file: TestFile, cloudStorage: CloudStorage, newFileUUID fileUUID: String, sharingGroupUUID: String, deviceUUID: String, testAccount: TestAccount) -> String? {
        let checkSum = file.checkSum(type: testAccount.scheme.accountName)

        let uploadRequest = UploadFileRequest()
        uploadRequest.fileUUID = fileUUID
        uploadRequest.mimeType = "text/plain"
        uploadRequest.sharingGroupUUID = sharingGroupUUID
        uploadRequest.checkSum = checkSum
    
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
        
        let accountManager = AccountManager(userRepository: UserRepository(db))
        let credentials = Credentials()
        accountManager.setupAccounts(credentials: credentials)
        
        guard let cloudStorage = FileController.getCreds(forUserId: addUserResponse.userId, from: db, accountManager: accountManager) as? CloudStorage else {
            XCTFail()
            return
        }
        
        let file: TestFile = .test1
        guard let fileName = uploadFile(file: file, cloudStorage: cloudStorage, newFileUUID: fileUUID, sharingGroupUUID: sharingGroupUUID, deviceUUID: deviceUUID, testAccount: .primaryOwningAccount) else {
            XCTFail()
            return
        }
        
        let options = CloudStorageFileNameOptions(cloudFolderName: ServerTestCase.cloudFolderName, mimeType: file.mimeType.rawValue)
                    
        let fileDeletion = FileDeletion(cloudStorage: cloudStorage, cloudFileName: fileName, options: options)

        let exp1 = expectation(description: "apply")
        FileDeletion.apply(deletions: [fileDeletion]) { error in
            XCTAssert(error == nil)
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
        
        let accountManager = AccountManager(userRepository: UserRepository(db))
        let credentials = Credentials()
        accountManager.setupAccounts(credentials: credentials)
        
        guard let cloudStorage = FileController.getCreds(forUserId: addUserResponse.userId, from: db, accountManager: accountManager) as? CloudStorage else {
            XCTFail()
            return
        }
        
        let file: TestFile = .test1
        guard let fileName1 = uploadFile(file: file, cloudStorage: cloudStorage, newFileUUID: fileUUID1, sharingGroupUUID: sharingGroupUUID, deviceUUID: deviceUUID, testAccount: .primaryOwningAccount) else {
            XCTFail()
            return
        }
        
        guard let fileName2 = uploadFile(file: file, cloudStorage: cloudStorage, newFileUUID: fileUUID2, sharingGroupUUID: sharingGroupUUID, deviceUUID: deviceUUID, testAccount: .primaryOwningAccount) else {
            XCTFail()
            return
        }
        
        let options = CloudStorageFileNameOptions(cloudFolderName: ServerTestCase.cloudFolderName, mimeType: file.mimeType.rawValue)
                    
        let fileDeletion1 = FileDeletion(cloudStorage: cloudStorage, cloudFileName: fileName1, options: options)
        let fileDeletion2 = FileDeletion(cloudStorage: cloudStorage, cloudFileName: fileName2, options: options)

        let exp1 = expectation(description: "apply")
        FileDeletion.apply(deletions: [fileDeletion1, fileDeletion2]) { error in
            XCTAssert(error == nil)
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
    
    // MARK: Tests with a file group
    
    func testFileDeletionWithOneFileAndOneFailure() {
        let deviceUUID = Foundation.UUID().uuidString
        let fileUUID1 = Foundation.UUID().uuidString
        let fileUUID2 = Foundation.UUID().uuidString // not uploaded
        let sharingGroupUUID = Foundation.UUID().uuidString

        guard let addUserResponse = self.addNewUser(testAccount:.primaryOwningAccount, sharingGroupUUID: sharingGroupUUID, deviceUUID:deviceUUID, cloudFolderName: ServerTestCase.cloudFolderName) else {
            XCTFail()
            return
        }
        
        let accountManager = AccountManager(userRepository: UserRepository(db))
        let credentials = Credentials()
        accountManager.setupAccounts(credentials: credentials)
        
        guard let cloudStorage = FileController.getCreds(forUserId: addUserResponse.userId, from: db, accountManager: accountManager) as? CloudStorage else {
            XCTFail()
            return
        }
        
        let file: TestFile = .test1
        guard let fileName1 = uploadFile(file: file, cloudStorage: cloudStorage, newFileUUID: fileUUID1, sharingGroupUUID: sharingGroupUUID, deviceUUID: deviceUUID, testAccount: .primaryOwningAccount) else {
            XCTFail()
            return
        }
        
        let options = CloudStorageFileNameOptions(cloudFolderName: ServerTestCase.cloudFolderName, mimeType: file.mimeType.rawValue)
                    
        let fileDeletion1 = FileDeletion(cloudStorage: cloudStorage, cloudFileName: fileName1, options: options)
        let fileDeletion2 = FileDeletion(cloudStorage: cloudStorage, cloudFileName: fileUUID2, options: options)

        let exp1 = expectation(description: "apply")
        
        // Put the bad file deletion first-- so we can show that the deletion continues on a failure.
        FileDeletion.apply(deletions: [fileDeletion2, fileDeletion1]) { error in
            XCTAssert(error != nil)
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
    
    func testApplyDeferredUploadsWithASingleFileAndOneChange() throws {
        let deviceUUID = Foundation.UUID().uuidString
        let fileUUID = Foundation.UUID().uuidString
        let fileGroupUUID = Foundation.UUID().uuidString

        let changeResolverName = CommentFile.changeResolverName

        // Do the v0 upload.
        guard let result = uploadTextFile(uploadIndex: 1, uploadCount: 1, deviceUUID:deviceUUID, fileUUID: fileUUID, stringFile: .commentFile, fileGroupUUID: fileGroupUUID, changeResolverName: changeResolverName),
            let sharingGroupUUID = result.sharingGroupUUID else {
            XCTFail()
            return
        }
        
        let messageString = "Example"
        let id = Foundation.UUID().uuidString
        var record = CommentFile.FixedObject()
        record[CommentFile.idKey] = id
        record["messageString"] = messageString
        let updateContents = try JSONSerialization.data(withJSONObject: record)
        
        
        let key = FileIndexRepository.LookupKey.primaryKeys(sharingGroupUUID: sharingGroupUUID, fileUUID: fileUUID)
        let lookupResult = FileIndexRepository(db).lookup(key: key, modelInit: FileIndex.init)
        
        guard case .found(let model) = lookupResult,
            let fileIndex = model as? FileIndex else {
            XCTFail()
            return
        }
        
        let deferredUpload = DeferredUpload()
        deferredUpload.fileGroupUUID = fileGroupUUID
        deferredUpload.status = .pending
        let addResult = DeferredUploadRepository(db).add(deferredUpload)
        guard case .success(deferredUploadId: let deferredUploadId) = addResult else {
            XCTFail()
            return
        }
        deferredUpload.deferredUploadId = deferredUploadId
        
        let upload = Upload()
        upload.deviceUUID = deviceUUID
        upload.fileUUID = fileUUID
        upload.fileVersion = 1
        upload.mimeType = "text/plain"
        upload.state = .uploadingFile
        upload.userId = fileIndex.userId
        upload.updateDate = Date()
        upload.sharingGroupUUID = sharingGroupUUID
        upload.uploadContents = updateContents
        upload.uploadCount = 1
        upload.uploadIndex = 1
        upload.deferredUploadId = deferredUploadId
        upload.v0UploadFileVersion = false
        
        let addUploadResult = UploadRepository(db).add(upload: upload, fileInFileIndex: true)
        guard case .success = addUploadResult else {
            XCTFail()
            return
        }
        
        let accountManager = AccountManager(userRepository: UserRepository(db))
        let credentials = Credentials()
        accountManager.setupAccounts(credentials: credentials)
        
        let resolverManager = ChangeResolverManager()
        
        do {
            try resolverManager.setupResolvers()
        } catch let error {
            XCTFail("\(error)")
            return
        }
        
        guard let applyDeferredUploads = try ApplyDeferredUploads(sharingGroupUUID: sharingGroupUUID, fileGroupUUID: fileGroupUUID, deferredUploads: [deferredUpload], accountManager: accountManager, resolverManager: resolverManager, db: db) else {
            XCTFail()
            return
        }
        
        let exp = expectation(description: "apply")
        
        applyDeferredUploads.run { error in
            XCTAssert(error == nil, "\(String(describing: error))")
            exp.fulfill()
        }
        
        waitExpectation(timeout: 10, handler: nil)
        
        // Need to download v1 of the file, read it and check it's contents.
        guard let cloudStorage = FileController.getCreds(forUserId: fileIndex.userId, from: db, accountManager: accountManager) as? CloudStorage else {
            XCTFail()
            return
        }
        
        let fileName = Filename.inCloud(deviceUUID: deviceUUID, fileUUID: fileUUID, mimeType: "text/plain", fileVersion: 1)
        let options = CloudStorageFileNameOptions(cloudFolderName: ServerTestCase.cloudFolderName, mimeType: "text/plain")

        var commentFile: CommentFile!
        let exp2 = expectation(description: "apply")
        cloudStorage.downloadFile(cloudFileName: fileName, options: options) { result in
            switch result {
            case .success(data: let data, checkSum: _):
                commentFile = try? CommentFile(with: data)
            default:
                XCTFail()
            }
            exp2.fulfill()
        }
        waitExpectation(timeout: 10, handler: nil)
        
        guard commentFile != nil, commentFile.count == 1 else {
            XCTFail()
            return
        }

        guard let record2 = commentFile[0] else {
            XCTFail()
            return
        }
        
        XCTAssert(record2[CommentFile.idKey] as? String == id)
        XCTAssert(record2["messageString"] as? String == messageString)
    }

    // I'm doing this using two DeferredUpload's -- to simulate the case where changes for the same file are uploaded in two separate batches. I.e., it probably doesn't make sense to think of multiple changes to the same file being uploaded in the same batch.
    func testApplyDeferredUploadsWithASingleFileAndTwoChanges() throws {
        let deviceUUID = Foundation.UUID().uuidString
        let fileUUID = Foundation.UUID().uuidString
        let fileGroupUUID = Foundation.UUID().uuidString

        let changeResolverName = CommentFile.changeResolverName

        // Do the v0 upload.
        guard let result = uploadTextFile(uploadIndex: 1, uploadCount: 1, deviceUUID:deviceUUID, fileUUID: fileUUID, stringFile: .commentFile, fileGroupUUID: fileGroupUUID, changeResolverName: changeResolverName),
            let sharingGroupUUID = result.sharingGroupUUID else {
            XCTFail()
            return
        }
        
        let messageString1 = "Example"
        let id1 = Foundation.UUID().uuidString
        var record1 = CommentFile.FixedObject()
        record1[CommentFile.idKey] = id1
        record1["messageString"] = messageString1
        let updateContents1 = try JSONSerialization.data(withJSONObject: record1)
        
        let messageString2 = "Another message"
        let id2 = Foundation.UUID().uuidString
        var record2 = CommentFile.FixedObject()
        record2[CommentFile.idKey] = id2
        record2["messageString"] = messageString2
        let updateContents2 = try JSONSerialization.data(withJSONObject: record2)
        
        let key = FileIndexRepository.LookupKey.primaryKeys(sharingGroupUUID: sharingGroupUUID, fileUUID: fileUUID)
        let lookupResult = FileIndexRepository(db).lookup(key: key, modelInit: FileIndex.init)
        
        guard case .found(let model) = lookupResult,
            let fileIndex = model as? FileIndex else {
            XCTFail()
            return
        }
        
        let deferredUpload1 = DeferredUpload()
        deferredUpload1.fileGroupUUID = fileGroupUUID
        deferredUpload1.status = .pending
        let addResult1 = DeferredUploadRepository(db).add(deferredUpload1)
        guard case .success(deferredUploadId: let deferredUploadId1) = addResult1 else {
            XCTFail()
            return
        }
        deferredUpload1.deferredUploadId = deferredUploadId1
        
        let deferredUpload2 = DeferredUpload()
        deferredUpload2.fileGroupUUID = fileGroupUUID
        deferredUpload2.status = .pending
        let addResult2 = DeferredUploadRepository(db).add(deferredUpload2)
        guard case .success(deferredUploadId: let deferredUploadId2) = addResult2 else {
            XCTFail()
            return
        }
        deferredUpload2.deferredUploadId = deferredUploadId2
        
        let upload1 = Upload()
        upload1.deviceUUID = deviceUUID
        upload1.fileUUID = fileUUID
        upload1.fileVersion = 1
        upload1.mimeType = "text/plain"
        upload1.state = .uploadingFile
        upload1.userId = fileIndex.userId
        upload1.updateDate = Date()
        upload1.sharingGroupUUID = sharingGroupUUID
        upload1.uploadContents = updateContents1
        upload1.uploadCount = 1
        upload1.uploadIndex = 1
        upload1.deferredUploadId = deferredUploadId1
        upload1.v0UploadFileVersion = false
        
        let addUploadResult = UploadRepository(db).add(upload: upload1, fileInFileIndex: true)
        guard case .success = addUploadResult else {
            XCTFail()
            return
        }
        
        let upload2 = Upload()
        upload2.deviceUUID = deviceUUID
        upload2.fileUUID = fileUUID
        upload2.fileVersion = 1
        upload2.mimeType = "text/plain"
        upload2.state = .uploadingFile
        upload2.userId = fileIndex.userId
        upload2.updateDate = Date()
        upload2.sharingGroupUUID = sharingGroupUUID
        upload2.uploadContents = updateContents2
        upload2.uploadCount = 1
        upload2.uploadIndex = 1
        upload2.deferredUploadId = deferredUploadId2
        upload2.v0UploadFileVersion = false
        
        let addUploadResult2 = UploadRepository(db).add(upload: upload2, fileInFileIndex: true)
        guard case .success = addUploadResult2 else {
            XCTFail()
            return
        }
        
        let accountManager = AccountManager(userRepository: UserRepository(db))
        let credentials = Credentials()
        accountManager.setupAccounts(credentials: credentials)
        
        let resolverManager = ChangeResolverManager()
        
        do {
            try resolverManager.setupResolvers()
        } catch let error {
            XCTFail("\(error)")
            return
        }
        
        guard let applyDeferredUploads = try ApplyDeferredUploads(sharingGroupUUID: sharingGroupUUID, fileGroupUUID: fileGroupUUID, deferredUploads: [deferredUpload1, deferredUpload2], accountManager: accountManager, resolverManager: resolverManager, db: db) else {
            XCTFail()
            return
        }
        
        let exp = expectation(description: "apply")
        
        applyDeferredUploads.run { error in
            XCTAssert(error == nil, "\(String(describing: error))")
            exp.fulfill()
        }
        
        waitExpectation(timeout: 10, handler: nil)
        
        // Need to download v1 of the file, read it and check it's contents.
        guard let cloudStorage = FileController.getCreds(forUserId: fileIndex.userId, from: db, accountManager: accountManager) as? CloudStorage else {
            XCTFail()
            return
        }
        
        let fileName = Filename.inCloud(deviceUUID: deviceUUID, fileUUID: fileUUID, mimeType: "text/plain", fileVersion: 1)
        let options = CloudStorageFileNameOptions(cloudFolderName: ServerTestCase.cloudFolderName, mimeType: "text/plain")

        var commentFile: CommentFile!
        let exp2 = expectation(description: "apply")
        cloudStorage.downloadFile(cloudFileName: fileName, options: options) { result in
            switch result {
            case .success(data: let data, checkSum: _):
                commentFile = try? CommentFile(with: data)
            default:
                XCTFail()
            }
            exp2.fulfill()
        }
        waitExpectation(timeout: 10, handler: nil)
        
        guard commentFile != nil, commentFile.count == 2 else {
            XCTFail()
            return
        }

        guard let outputRecord1 = commentFile[0] else {
            XCTFail()
            return
        }
        
        XCTAssert(outputRecord1[CommentFile.idKey] as? String == id1)
        XCTAssert(outputRecord1["messageString"] as? String == messageString1)
        
        
        guard let outputRecord2 = commentFile[1] else {
            XCTFail()
            return
        }
        
        XCTAssert(outputRecord2[CommentFile.idKey] as? String == id2)
        XCTAssert(outputRecord2["messageString"] as? String == messageString2)
    }
}
