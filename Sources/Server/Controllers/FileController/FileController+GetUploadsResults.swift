//
//  FileController+GetUploadsResults.swift
//  Server
//
//  Created by Christopher G Prince on 8/9/20.
//

import Foundation
import ServerShared
import LoggerAPI

extension FileController {
    func getUploadsResults(params:RequestProcessingParameters) {
        guard let getUploadsRequest = params.request as? GetUploadsResultsRequest else {
            let message = "Did not receive GetUploadsResultsRequest"
            Log.error(message)
            params.completion(.failure(.message(message)))
            return
        }
        
        guard let deferredUploadId = getUploadsRequest.deferredUploadId else {
            let message = "Could not get deferredUploadId."
            Log.error(message)
            params.completion(.failure(.message(message)))
            return
        }
        
        guard let signedInUserId = params.currentSignedInUser?.userId else {
            let message = "Could not get signedInUserId."
            Log.error(message)
            params.completion(.failure(.message(message)))
            return
        }

        let key = DeferredUploadRepository.LookupKey.deferredUploadId(deferredUploadId)
        let deferredUploadResult = params.repos.deferredUpload.lookup(key: key, modelInit: DeferredUpload.init)
        
        switch deferredUploadResult {
        case .found(let model):
            guard let deferredUpload = model as? DeferredUpload else {
                let message = "Problem coercing to DeferredUpload."
                Log.error(message)
                params.completion(.failure(.message(message)))
                return
            }
            
            guard deferredUpload.userId == signedInUserId else {
                let message = "Attempting to get DeferredUpload record for different user."
                Log.error(message)
                params.completion(.failure(.message(message)))
                return
            }
            
            let response = GetUploadsResultsResponse()
            response.status = deferredUpload.status
            params.completion(.success(response))
            
        case .noObjectFound:
            let response = GetUploadsResultsResponse()
            params.completion(.success(response))
            
        case .error(let error):
            let message = "Problem with deferredUpload.lookup: \(error)"
            Log.error(message)
            params.completion(.failure(.message(message)))
        }
    }
}
