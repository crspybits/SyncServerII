//
//  FinishUploadDeletion.swift
//  Server
//
//  Created by Christopher G Prince on 7/31/20.
//

// This is the replacement for DoneUploads. It's not invoked from an endpoint, but rather from UploadDeletion.

import Foundation
import LoggerAPI

class FinishUploadDeletion {
    private let type: DeletionsType
    private let uploader: UploaderProtocol
    private let sharingGroupUUID: String
    private let params: RequestProcessingParameters
    
    enum Errors: Error {
        case badFinishUploadsType
    }
     
    enum DeletionsType {
        case singleFile(upload: Upload)
        case fileGroup(fileGroupUUID: String)
    }
    
    init(type: DeletionsType, uploader: UploaderProtocol, sharingGroupUUID: String, params: RequestProcessingParameters) {
        self.type = type
        self.uploader = uploader
        self.sharingGroupUUID = sharingGroupUUID
        self.params = params
    }
    
    enum DeletionsResponse {
        case deferred(runner: RequestHandler.PostRequestRunner)
        case error
    }
    
    func finish() throws -> DeletionsResponse {
        let deferredUpload = DeferredUpload()
        deferredUpload.status = .pendingDeletion
        deferredUpload.sharingGroupUUID = sharingGroupUUID
        
        switch type {
        case .fileGroup(fileGroupUUID: let fileGroupUUID):
            deferredUpload.fileGroupUUID = fileGroupUUID
        case .singleFile:
            break
        }
        
        let result = params.repos.deferredUpload.retry {[unowned self] in
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
            let result = params.repos.upload.update(indexId: upload.uploadId, with: [Upload.deferredUploadIdKey: .int64(deferredUploadId)])
            guard result else {
                Log.error("Failed updating upload.")
                return .error
            }
        }
        
        return .deferred(runner: { try self.uploader.run() })
    }
}
