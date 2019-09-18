//
//  MicrosoftCreds+Uploads.swift
//  Server
//
//  Created by Christopher G Prince on 9/15/19.
//

import Foundation
import LoggerAPI
import HeliumLogger
import KituraNet
import SyncServerShared

extension MicrosoftCreds {
    struct UploadSession: Decodable {
        let uploadUrl: String
    }
    
    func createUploadSession(cloudFileName: String, completion:@escaping (Result<UploadSession>)->()) {
    
        // https://docs.microsoft.com/en-us/onedrive/developer/rest-api/api/driveitem_createuploadsession?view=odsp-graph-online#create-an-upload-session
    
        // POST /drive/root:/{item-path}:/createUploadSession
        // Content-Type: application/json
        
        let path = "/me/drive/special/approot:/\(cloudFileName):/createUploadSession"
        guard let encodedPath = encoded(string: path) else {
            Log.error("Failed encoding path.")
            completion(.failure(OneDriveFailure.urlEncoding))
            return
        }
        
        let bodyDict = [
            "item": [
                "@microsoft.graph.conflictBehavior": "fail"
            ]
        ]
        
        guard let jsonString = JSONExtras.toJSONString(dict: bodyDict) else {
            completion(.failure(OneDriveFailure.couldNotEncodeBody))
            return
        }
        
        self.apiCall(method: "POST", baseURL: graphBaseURL, path: encodedPath, additionalHeaders: basicHeaders(), body: .string(jsonString), expectedSuccessBody: .data, expectedFailureBody: .data) { apiResult, statusCode, responseHeaders in
        
            Log.debug("apiResult: \(String(describing: apiResult)); statusCode: \(String(describing: statusCode))")
            
            guard let apiResult = apiResult else {
                completion(.failure(OneDriveFailure.noAPIResult))
                return
            }
            
            guard case .data(let data) = apiResult else {
                completion(.failure(OneDriveFailure.noDataInAPIResult))
                return
            }
            
            let decoder = JSONDecoder()

            guard statusCode == HTTPStatusCode.OK else {
                guard let errorResult = try? decoder.decode(ErrorResult.self, from: data) else {
                    completion(.failure(OneDriveFailure.couldNotDecodeError))
                    return
                }
                
                guard !self.accessTokenIsRevokedOrExpired(errorResult: errorResult, statusCode: statusCode) else {
                    completion(.accessTokenRevokedOrExpired)
                    return
                }
                
                completion(.failure(OneDriveFailure.badStatusCode(statusCode, errorResult)))
                return
            }
            
            guard let uploadSession = try? decoder.decode(UploadSession.self, from: data) else {
                completion(.failure(OneDriveFailure.couldNotDecodeResult))
                return
            }
            
            completion(.success(uploadSession))
        }
    }
    
    class UploadState {
        let numberBytesInFile: UInt
        let blockSize: UInt
        let data: Data
        let numberFullBlocks: UInt
        let partialLastBlock: Bool
        let partialLastBlockLength: UInt

        private(set) var currentStartOffset: Data.Index
        private(set) var currentEndOffset: Data.Index
        private(set) var currentBlock: Int = 0
        
        var contentRange: String {
            let startByte = currentStartOffset
            let endByte = currentEndOffset - 1
            let numberBytes =  numberBytesInFile
            return "bytes \(startByte)-\(endByte)/\(numberBytes)"
        }

        static let blockMultipleInBytes = 327680
        
        // The size of each byte range MUST be a multiple of 320 KiB (327,680 bytes).
        // checkBlockSize set to false is for testing.
        init?(blockSize: UInt, data: Data, checkBlockSize: Bool = true) {
            if data.count == 0 || blockSize == 0 {
                return nil
            }
            
            if checkBlockSize {
                guard Int(blockSize) % MicrosoftCreds.UploadState.blockMultipleInBytes == 0 else {
                    return nil
                }
            }
            
            numberBytesInFile = UInt(data.count)
            self.blockSize = blockSize
            self.data = data
            numberFullBlocks = numberBytesInFile / blockSize
            partialLastBlockLength = numberBytesInFile % blockSize
            partialLastBlock = partialLastBlockLength != 0
            
            currentStartOffset = data.startIndex
            
            if numberFullBlocks > 0 {
                currentEndOffset = data.index(data.startIndex, offsetBy: Int(blockSize))
            }
            else {
                currentEndOffset = data.index(data.startIndex, offsetBy: Int(partialLastBlockLength))
            }
        }
        
        func getCurrentBlock() -> Data {
            let range = currentStartOffset..<currentEndOffset
            return data.subdata(in: range)
        }
        
        // Returns true iff could advance. Returning false indicate we're out data.
        func advanceToNextBlock() -> Bool {
            currentBlock += 1
            
            if currentBlock < numberFullBlocks {
                currentStartOffset = currentEndOffset
                currentEndOffset = data.index(currentStartOffset, offsetBy: Int(blockSize))
                
                return true
            }
            else if currentBlock == numberFullBlocks && partialLastBlock {
                currentStartOffset = currentEndOffset
                currentEndOffset = data.index(currentStartOffset, offsetBy: Int(partialLastBlockLength))
                return true
            }
            
            return false
        }
    }
    
    // The completion handler is called, with the file checksum, when the entire upload is complete.
    func uploadBytes(toUploadSession uploadSession: UploadSession, withUploadState uploadState: UploadState, completion:@escaping (Result<String>)->()) {
        // Content-Length: 26
        // Content-Range: bytes 0-25/128
        
        let urlString = uploadSession.uploadUrl
        
        guard let components = URLComponents(string: urlString),
            let host = components.host else {
            completion(.failure(OneDriveFailure.urlEncoding))
            return
        }
        
        let dataSubrange = uploadState.getCurrentBlock()
        
        var headers = basicHeaders()
        headers["Content-Length"] = "\(dataSubrange.count)"
        headers["Content-Range"] = uploadState.contentRange
        
        Log.debug("Upload content range: \(uploadState.contentRange)")

        self.apiCall(method: "PUT", baseURL: host, path: components.path, additionalHeaders: headers, body: .data(dataSubrange), expectedSuccessBody: .data, expectedFailureBody: .data) { apiResult, statusCode, responseHeaders in
        
            Log.debug("apiResult: \(String(describing: apiResult)); statusCode: \(String(describing: statusCode))")

            guard let apiResult = apiResult else {
                completion(.failure(OneDriveFailure.noAPIResult))
                return
            }
        
            guard case .data(let data) = apiResult else {
                completion(.failure(OneDriveFailure.noDataInAPIResult))
                return
            }
        
            let decoder = JSONDecoder()
            
            guard statusCode == HTTPStatusCode.OK ||
                statusCode == HTTPStatusCode.created ||
                statusCode == HTTPStatusCode.accepted else {

                guard let errorResult = try? decoder.decode(ErrorResult.self, from: data) else {
                    completion(.failure(OneDriveFailure.couldNotDecodeError))
                    return
                }
                
                guard !self.accessTokenIsRevokedOrExpired(errorResult: errorResult, statusCode: statusCode) else {
                    completion(.accessTokenRevokedOrExpired)
                    return
                }
                
                completion(.failure(OneDriveFailure.badStatusCode(statusCode, errorResult)))
                return
            }
            
            if uploadState.advanceToNextBlock() {
                self.uploadBytes(toUploadSession: uploadSession, withUploadState: uploadState, completion: completion)
            }
            else {
                guard let fileResult = try? decoder.decode(FileResult.self, from: data) else {
                    completion(.failure(OneDriveFailure.couldNotDecodeResult))
                    return
                }
                
                completion(.success(fileResult.file.hashes.sha1Hash))
            }
        }
    }
    
    // String in successful result is checksum.
    func uploadFileUsingSession(withName fileName: String, mimeType: MimeType, data:Data, completion:@escaping (Result<String>)->()) {
        let blockSize = MicrosoftCreds.UploadState.blockMultipleInBytes * 4
        
        createUploadSession(cloudFileName: fileName) {[weak self] result in
            guard let self = self else {
                completion(.failure(OneDriveFailure.couldNotGetSelf))
                return
            }
            
            switch result {
            case .failure(let error):
                completion(.failure(error))
            case .accessTokenRevokedOrExpired:
                completion(.accessTokenRevokedOrExpired)
                
            case .success(let session):
                guard let state = MicrosoftCreds.UploadState(blockSize: UInt(blockSize), data: data) else {
                    completion(.failure(OneDriveFailure.couldNotCreateUploadState))
                    return
                }
            
                self.uploadBytes(toUploadSession: session, withUploadState: state) { result in
                    switch result {
                    case .success(let checkSum):
                        completion(.success(checkSum))
                    case .failure(let error):
                        completion(.failure(error))
                    case .accessTokenRevokedOrExpired:
                        completion(.accessTokenRevokedOrExpired)
                    }
                }
            }
        }
    }
}
