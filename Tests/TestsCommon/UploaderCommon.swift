//
//  UploaderCommon.swift
//  AccountFileTests
//
//  Created by Christopher G Prince on 7/21/20.
//

@testable import Server
import ServerShared
import ChangeResolvers
import XCTest
import ServerAccount
import LoggerAPI

private enum Errors: Error {
    case errorLookingUpFile
}
    
public struct ExampleComment {
    static let messageKey = "messageString"
    public let messageString:String
    public let id: String
    
    public var record:CommentFile.FixedObject {
        var result = CommentFile.FixedObject()
        result[CommentFile.idKey] = id
        result[Self.messageKey] = messageString
        return result
    }
    
    public var updateContents: Data {
        return try! JSONSerialization.data(withJSONObject: record)
    }
}

public protocol UploaderCommon {
    var accountManager:AccountManager! {get}
    var db:Database! {get}
    func expectation(description: String) -> XCTestExpectation
    func waitForExpectations(timeout: TimeInterval, handler: XCWaitCompletionHandler?)
}

public extension UploaderCommon {
    func downloadCommentFile(fileName: String, userId: UserId) -> CommentFile? {
        guard let cloudStorage = FileController.getCreds(forUserId: userId, userRepo: UserRepository(db), accountManager: accountManager, accountDelegate: nil)?.cloudStorage(mock: MockStorage()) else {
            XCTFail()
            return nil
        }
        
        let options = CloudStorageFileNameOptions(cloudFolderName: ServerTestCase.cloudFolderName, mimeType: "text/plain")

        var commentFile: CommentFile?
        
        let exp2 = expectation(description: "apply")
        cloudStorage.downloadFile(cloudFileName: fileName, options: options) { result in
            switch result {
            case .success(data: let data, checkSum: _):
                commentFile = try? CommentFile(with: data)
            default:
                XCTFail("\(result)")
            }
            exp2.fulfill()
        }
        waitForExpectations(timeout: 10, handler: nil)
        
        return commentFile
    }
    
    internal func createUploadForTextFile(deviceUUID: String, fileUUID: String, fileGroup: ServerTestCase.FileGroup? = nil, sharingGroupUUID: String, userId: UserId, deferredUploadId: Int64? = nil, updateContents: Data? = nil, uploadCount: Int32 = 1, uploadIndex:Int32 = 1, state:UploadState = .vNUploadFileChange) -> Upload? {
        let upload = Upload()
        upload.deviceUUID = deviceUUID
        upload.fileUUID = fileUUID
        upload.mimeType = "text/plain"
        upload.state = state
        upload.userId = userId
        upload.updateDate = Date()
        upload.sharingGroupUUID = sharingGroupUUID
        upload.uploadContents = updateContents
        upload.uploadCount = uploadCount
        upload.uploadIndex = uploadIndex
        upload.deferredUploadId = deferredUploadId
        upload.fileGroupUUID = fileGroup?.fileGroupUUID
        upload.objectType = fileGroup?.objectType
        
        let addUploadResult = UploadRepository(db).add(upload: upload, fileInFileIndex: true)
        guard case .success(let uploadId) = addUploadResult else {
            return nil
        }
        
        upload.uploadId = uploadId
        
        return upload
    }
    
    func createDeferredUpload(userId: UserId, fileGroupUUID: String? = nil, sharingGroupUUID: String, status: DeferredUploadStatus) -> DeferredUpload? {
        let deferredUpload = DeferredUpload()
        deferredUpload.fileGroupUUID = fileGroupUUID
        deferredUpload.status = status
        deferredUpload.sharingGroupUUID = sharingGroupUUID
        deferredUpload.userId = userId
        let addResult = DeferredUploadRepository(db).add(deferredUpload)
        guard case .success(deferredUploadId: let deferredUploadId) = addResult else {
            return nil
        }
        deferredUpload.deferredUploadId = deferredUploadId
        return deferredUpload
    }
    
    func getFileIndex(sharingGroupUUID: String, fileUUID: String) -> FileIndex? {
        let key = FileIndexRepository.LookupKey.primaryKeys(sharingGroupUUID: sharingGroupUUID, fileUUID: fileUUID)
        let lookupResult = FileIndexRepository(db).lookup(key: key, modelInit: FileIndex.init)
        
        guard case .found(let model) = lookupResult,
            let fileIndex = model as? FileIndex else {
            return nil
        }
        
        return fileIndex
    }
    
    // Download the comment file and check it against the expectedCommentFile.
    func checkCommentFile(expectedComment: ExampleComment, recordIndex: Int = 0, recordCount: Int = 1, fileVersion: FileVersionInt = 1, deviceUUID: String, fileUUID: String, userId: UserId) -> Bool {
        let fileName = Filename.inCloud(deviceUUID: deviceUUID, fileUUID: fileUUID, mimeType: "text/plain", fileVersion: fileVersion)
        
        guard let commentFile = downloadCommentFile(fileName: fileName, userId: userId) else {
            XCTFail()
            return false
        }
        
        guard commentFile.count == recordCount else {
            XCTFail()
            return false
        }

        guard let record = commentFile[recordIndex] else {
            XCTFail()
            return false
        }
        
        guard record[CommentFile.idKey] as? String == expectedComment.id else {
            XCTFail()
            return false
        }
        
        guard record["messageString"] as? String == expectedComment.messageString else {
            XCTFail()
            return false
        }
        
        return true
    }
    
    func fileIsInCloudStorage(fileIndex: FileIndex, services: UploaderServices) throws -> Bool {
        var boolResult: Bool = false
        
        let exp2 = expectation(description: "run")

        // Need to make sure the file has been removed from cloud storage.
        let (_, cloudStorage) = try fileIndex.getCloudStorage(userRepo: UserRepository(db), services: services)
        let cloudFileName = Filename.inCloud(deviceUUID: fileIndex.deviceUUID, fileUUID: fileIndex.fileUUID, mimeType: fileIndex.mimeType, fileVersion: fileIndex.fileVersion)
        let options = CloudStorageFileNameOptions(cloudFolderName: ServerTestCase.cloudFolderName, mimeType: fileIndex.mimeType)
        
        var error: Error?
        
        cloudStorage.lookupFile(cloudFileName: cloudFileName, options: options) { result in
            switch result {
            case .success(let found):
                boolResult = found
                Log.debug("cloudStorage.lookupFile: \(found)")
            default:
                error = Errors.errorLookingUpFile
            }
            
            exp2.fulfill()
        }
        
        waitForExpectations(timeout: 10, handler: nil)
        
        if let resultError = error {
            throw resultError
        }
        
        return boolResult
    }
}

