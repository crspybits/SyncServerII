//
//  FinishUploadDeletion.swift
//  Server
//
//  Created by Christopher G Prince on 7/31/20.
//

// This is the replacement for DoneUploads. It's not invoked from an endpoint, but rather from UploadDeletion.

import Foundation
import LoggerAPI
import ServerShared

class FinishUploadDeletion {
    private let type: DeletionsType
    private let uploader: UploaderProtocol
    private let sharingGroupUUID: String
    private var params: FinishUploadsParameters
    private let currentSignedInUser: UserId
    
    enum Errors: Error {
        case badFinishUploadsType
        case noUserId
    }
     
    enum DeletionsType {
        case singleFile(upload: Upload)
        case fileGroup(fileGroupUUID: String)
    }
    
    init(type: DeletionsType, uploader: UploaderProtocol, sharingGroupUUID: String, params:FinishUploadsParameters) throws {
        self.type = type
        self.uploader = uploader
        self.sharingGroupUUID = sharingGroupUUID
        self.params = params
        
        guard let userId = self.params.currentSignedInUser?.userId else {
            throw Errors.noUserId
        }
        
        self.currentSignedInUser = userId
    }
    
    enum DeletionsResponse {
        case deferred(deferredUploadId: Int64, runner: RequestHandler.PostRequestRunner)
        case error
    }
    
    func finish() throws -> DeletionsResponse {
        let deferredUpload = DeferredUpload()
        deferredUpload.status = .pendingDeletion
        deferredUpload.sharingGroupUUID = sharingGroupUUID
        deferredUpload.userId = currentSignedInUser
        
        switch type {
        case .fileGroup(fileGroupUUID: let fileGroupUUID):
            deferredUpload.fileGroupUUID = fileGroupUUID
        case .singleFile:
            break
        }
        
        let result = params.repos.deferredUpload.retry { [unowned self] in
            return self.params.repos.deferredUpload.add(deferredUpload)
        }
        
        let deferredUploadId: Int64
        
        switch result {
        case .success(deferredUploadId: let id):
            deferredUploadId = id
            
        default:
            Log.error("Failed inserting DeferredUpload: \(result)")
            return .error
        }
        
        switch type {
        case .fileGroup:
            break
        case .singleFile(let upload):
            guard let uploadId = upload.uploadId else {
                Log.error("Upload didn't have an id")
                return .error
            }
            
            let result = params.repos.upload.update(indexId: uploadId, with: [Upload.deferredUploadIdKey: .int64(deferredUploadId)])
            guard result else {
                Log.error("Failed updating upload.")
                return .error
            }
        }
        
        return .deferred(deferredUploadId: deferredUploadId, runner: { try self.uploader.run() })
    }
}
