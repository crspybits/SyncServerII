//
//  ServerAPI.swift
//  Pods
//
//  Created by Christopher Prince on 12/24/16.
//
//

import Foundation
import SMCoreLib

public protocol ServerAPIDelegate : class {
    func deviceUUID(forServerAPI: ServerAPI) -> Foundation.UUID
    
#if DEBUG
    func doneUploadsRequestTestLockSync() -> TimeInterval?
#endif
}

public class ServerAPI {
    // These need to be set by user of this class.
    public var baseURL:String!
    public weak var delegate:ServerAPIDelegate!
    
    fileprivate var authTokens:[String:String]?
    
    public enum ServerAPIError : Error {
    case non200StatusCode(Int)
    case badStatusCode(Int)
    }
    
    // If this is nil, you must use the ServerNetworking authenticationDelegate to provide credentials.
    public var creds:SignInCreds? {
        didSet {
            if creds == nil {
                ServerNetworking.session.authenticationDelegate = nil
            }
            else {
                ServerNetworking.session.authenticationDelegate = self
                self.authTokens = creds!.authDict()
            }
        }
    }

    public static let session = ServerAPI()
    
    fileprivate init() {
    }
    
    // MARK: Health check

    private func checkForError(statusCode:Int?, error:Error?) -> Error? {
        if statusCode == HTTPStatus.ok.rawValue || statusCode == nil {
            return error
        }
        else {
            return ServerAPIError.non200StatusCode(statusCode!)
        }
    }
    
    public func healthCheck(completion:((Error?)->(Void))?) {
        let endpoint = ServerEndpoints.healthCheck
        let url = URL(string: baseURL + endpoint.path)!
        
        ServerNetworking.session.sendRequestUsing(method: endpoint.method, toURL: url) { (response,  httpStatus, error) in
            completion?(self.checkForError(statusCode: httpStatus, error: error))
        }
    }

    // MARK: Authentication/user-sign in
    
    // Adds the user specified by the creds property (or authenticationDelegate in ServerNetworking if that is nil).
    public func addUser(completion:((Error?)->(Void))?) {
        let endpoint = ServerEndpoints.addUser
        let url = URL(string: baseURL + endpoint.path)!
        
        ServerNetworking.session.sendRequestUsing(method: endpoint.method,
            toURL: url) { (response,  httpStatus, error) in
            completion?(self.checkForError(statusCode: httpStatus, error: error))
        }
    }
    
    public func checkCreds(completion:((_ userExists:Bool?, Error?)->(Void))?) {
        let endpoint = ServerEndpoints.checkCreds
        let url = URL(string: baseURL + endpoint.path)!
        
        ServerNetworking.session.sendRequestUsing(method: endpoint.method,
            toURL: url) { (response, httpStatus, error) in
            
            var userExists:Bool?
            if httpStatus == HTTPStatus.ok.rawValue {
                userExists = true
            }
            else if httpStatus == HTTPStatus.unauthorized.rawValue {
                userExists = false
            }
            
            if userExists == nil {
                let result = self.checkForError(statusCode: httpStatus, error: error)
                assert(result != nil)
                completion?(nil, result)
            }
            else {
                completion?(userExists, nil)
            }
        }
    }
    
    public func removeUser(completion:((Error?)->(Void))?) {
        let endpoint = ServerEndpoints.removeUser
        let url = URL(string: baseURL + endpoint.path)!
        
        ServerNetworking.session.sendRequestUsing(method: endpoint.method, toURL: url) { (response,  httpStatus, error) in
            completion?(self.checkForError(statusCode: httpStatus, error: error))
        }
    }
    
    // MARK: Files
    
    public enum FileIndexError : Error {
    case fileIndexResponseConversionError
    case couldNotCreateFileIndexRequest
    }
        
    public func fileIndex(completion:((_ fileIndex: [FileInfo]?, _ masterVersion:MasterVersionInt?, Error?)->(Void))?) {
    
        let endpoint = ServerEndpoints.fileIndex
        
        let url = URL(string: baseURL + endpoint.path)!
        
        ServerNetworking.session.sendRequestUsing(method: endpoint.method, toURL: url) { (response,  httpStatus, error) in
            let resultError = self.checkForError(statusCode: httpStatus, error: error)
            
            if resultError == nil {
                if let fileIndexResponse = FileIndexResponse(json: response!) {
                    completion?(fileIndexResponse.fileIndex, fileIndexResponse.masterVersion, nil)
                }
                else {
                    completion?(nil, nil, FileIndexError.fileIndexResponseConversionError)
                }
            }
            else {
                completion?(nil, nil, resultError)
            }
        }
    }
    
    public struct File {
        let localURL:URL!
        let fileUUID:String!
        let mimeType:String!
        let cloudFolderName:String!
        let deviceUUID:String!
        let appMetaData:String?
        let fileVersion:FileVersionInt!
    }
    
    public enum UploadFileError : Error {
    case couldNotCreateUploadFileRequest
    case couldNotReadUploadFile
    case noExpectedResultKey
    }
    
    public enum UploadFileResult {
    case success(sizeInBytes:Int64)
    case serverMasterVersionUpdate(Int64)
    }
    
    public func uploadFile(file:File, serverMasterVersion:MasterVersionInt, completion:((UploadFileResult?, Error?)->(Void))?) {
        let endpoint = ServerEndpoints.uploadFile

        Log.special("file.fileUUID: \(file.fileUUID)")
        
        let params:[String : Any] = [
            UploadFileRequest.fileUUIDKey: file.fileUUID,
            UploadFileRequest.mimeTypeKey: file.mimeType,
            UploadFileRequest.cloudFolderNameKey: file.cloudFolderName,
            UploadFileRequest.appMetaDataKey: file.appMetaData,
            UploadFileRequest.fileVersionKey: file.fileVersion,
            UploadFileRequest.masterVersionKey: serverMasterVersion
        ]
        
        guard let uploadRequest = UploadFileRequest(json: params) else {
            completion?(nil, UploadFileError.couldNotCreateUploadFileRequest);
            return;
        }
        
        assert(endpoint.method == .post)
        
        guard let fileData = try? Data(contentsOf: file.localURL) else {
            completion?(nil, UploadFileError.couldNotReadUploadFile);
            return;
        }
        
        let parameters = uploadRequest.urlParameters()!
        let url = URL(string: baseURL + endpoint.path + "/?" + parameters)!
        
        ServerNetworking.session.postUploadDataTo(url, dataToUpload: fileData) { (resultDict, httpStatus, error) in
        
            let resultError = self.checkForError(statusCode: httpStatus, error: error)

            if resultError == nil {
                if let size = resultDict?[UploadFileResponse.sizeKey] as? Int64 {
                    completion?(UploadFileResult.success(sizeInBytes:size), nil)
                }
                else if let versionUpdate = resultDict?[UploadFileResponse.masterVersionUpdateKey] as? Int64 {
                    completion?(UploadFileResult.serverMasterVersionUpdate(versionUpdate), nil)
                }
                else {
                    completion?(nil, UploadFileError.noExpectedResultKey)
                }
            }
            else {
                completion?(nil, resultError)
            }
        }
    }
    
    public enum DoneUploadsError : Error {
    case noExpectedResultKey
    case couldNotCreateDoneUploadsRequest
    }
    
    public enum DoneUploadsResult {
    case success(numberUploadsTransferred:Int64)
    case serverMasterVersionUpdate(Int64)
    }
    
    public func doneUploads(serverMasterVersion:MasterVersionInt!, completion:((DoneUploadsResult?, Error?)->(Void))?) {
        let endpoint = ServerEndpoints.doneUploads
        
        let deviceUUID = delegate.deviceUUID(forServerAPI: self).uuidString

        var params = [String : Any]()
        params[DoneUploadsRequest.masterVersionKey] = serverMasterVersion
        
#if DEBUG
        if let testLockSync = delegate.doneUploadsRequestTestLockSync() {
            params[DoneUploadsRequest.testLockSyncKey] = Int32(testLockSync)
        }
#endif
        
        guard let doneUploadsRequest = DoneUploadsRequest(json: params) else {
            completion?(nil, DoneUploadsError.couldNotCreateDoneUploadsRequest);
            return;
        }

        let parameters = doneUploadsRequest.urlParameters()!
        let url = URL(string: baseURL + endpoint.path + "/?" + parameters)!

        ServerNetworking.session.sendRequestUsing(method: endpoint.method, toURL: url) { (response,  httpStatus, error) in
        
            let resultError = self.checkForError(statusCode: httpStatus, error: error)

            if resultError == nil {
                if let numberUploads = response?[DoneUploadsResponse.numberUploadsTransferredKey] as? Int64 {
                    completion?(DoneUploadsResult.success(numberUploadsTransferred:numberUploads), nil)
                }
                else if let masterVersionUpdate = response?[DoneUploadsResponse.masterVersionUpdateKey] as? Int64 {
                    completion?(DoneUploadsResult.serverMasterVersionUpdate(masterVersionUpdate), nil)
                } else {
                    completion?(nil, DoneUploadsError.noExpectedResultKey)
                }
            }
            else {
                completion?(nil, resultError)
            }
        }
    }
        
    public struct FileToDownload {
        let fileUUID:String!
        let cloudFolderName:String!
        let fileVersion:FileVersionInt!
    }
    
    public enum DownloadFileResult {
    case success(url: SMRelativeLocalURL, fileSizeBytes:Int64, appMetaData:String?)
    case serverMasterVersionUpdate(Int64)
    }
    
    public enum DownloadFileError : Error {
    case couldNotCreateDownloadFileRequest
    case obtainedAppMetaDataButWasNotString
    case noExpectedResultKey
    case nilResponse
    case couldNotObtainHeaderParameters
    case resultURLObtainedWasNil
    }
    
    public func downloadFile(file: FileToDownload, serverMasterVersion:MasterVersionInt!, completion:((DownloadFileResult?, Error?)->(Void))?) {
        let endpoint = ServerEndpoints.downloadFile
        
        let deviceUUID = delegate.deviceUUID(forServerAPI: self).uuidString

        var params = [String : Any]()
        params[DownloadFileRequest.masterVersionKey] = serverMasterVersion
        params[DownloadFileRequest.fileUUIDKey] = file.fileUUID
        params[DownloadFileRequest.cloudFolderNameKey] = file.cloudFolderName
        params[DownloadFileRequest.fileVersionKey] = file.fileVersion

        guard let downloadFileRequest = DownloadFileRequest(json: params) else {
            completion?(nil, DownloadFileError.couldNotCreateDownloadFileRequest)
            return
        }

        let parameters = downloadFileRequest.urlParameters()!
        let serverURL = URL(string: baseURL + endpoint.path + "/?" + parameters)!

        ServerNetworking.session.downloadFrom(serverURL, method: endpoint.method) { (resultURL, response, error) in
        
            guard response != nil else {
                let resultError = error ?? DownloadFileError.nilResponse
                completion?(nil, resultError)
                return
            }
            
            let resultError = self.checkForError(statusCode: response!.statusCode, error: error)

            if resultError == nil {
                if let parms = response!.allHeaderFields[ServerConstants.httpResponseMessageParams] as? String,
                    let jsonDict = self.toJSONDictionary(jsonString: parms) {
                    Log.msg("jsonDict: \(jsonDict)")

                    if let fileSizeBytes = jsonDict[DownloadFileResponse.fileSizeBytesKey] as? Int64 {
                        var appMetaDataString:String?
                        var appMetaData = jsonDict[DownloadFileResponse.appMetaDataKey]
                        if appMetaData != nil {
                            if appMetaData is String {
                                appMetaDataString = appMetaData as! String
                            }
                            else {
                                completion?(nil, DownloadFileError.obtainedAppMetaDataButWasNotString)
                                return
                            }
                        }
                        
                        guard resultURL != nil else {
                            completion?(nil, DownloadFileError.resultURLObtainedWasNil)
                            return
                        }
                        
                        completion?(.success(url: resultURL!, fileSizeBytes:fileSizeBytes, appMetaData:appMetaDataString), nil)
                    }
                    else if let masterVersionUpdate = jsonDict[DownloadFileResponse.masterVersionUpdateKey] as? Int64 {
                        completion?(DownloadFileResult.serverMasterVersionUpdate(masterVersionUpdate), nil)
                    } else {
                        completion?(nil, DownloadFileError.noExpectedResultKey)
                    }
                }
                else {
                    completion?(nil, DownloadFileError.couldNotObtainHeaderParameters)
                }
            }
            else {
                completion?(nil, resultError)
            }
        }
    }
    
    private func toJSONDictionary(jsonString:String) -> [String:Any]? {
        guard let data = jsonString.data(using: String.Encoding.utf8) else {
            return nil
        }
        
        var json:Any?
        
        do {
            try json = JSONSerialization.jsonObject(with: data, options: JSONSerialization.ReadingOptions(rawValue: UInt(0)))
        } catch (let error) {
            Log.error("Error in JSON conversion: \(error)")
            return nil
        }
        
        guard let jsonDict = json as? [String:Any] else {
            Log.error("Could not convert json to json Dict")
            return nil
        }
        
        return jsonDict
    }
    
    public enum GetUploadsError : Error {
    case getUploadsResponseConversionError
    case couldNotCreateFileIndexRequest
    }
        
    public func getUploads(completion:((_ fileIndex: [FileInfo]?, Error?)->(Void))?) {
    
        let endpoint = ServerEndpoints.getUploads
        
        let url = URL(string: baseURL + endpoint.path)!
        
        ServerNetworking.session.sendRequestUsing(method: endpoint.method, toURL: url) { (response,  httpStatus, error) in
            let resultError = self.checkForError(statusCode: httpStatus, error: error)
            
            if resultError == nil {
                if let getUploadsResponse = GetUploadsResponse(json: response!) {
                    completion?(getUploadsResponse.uploads, nil)
                }
                else {
                    completion?(nil, GetUploadsError.getUploadsResponseConversionError)
                }
            }
            else {
                completion?(nil, resultError)
            }
        }
    }
}

extension ServerAPI : ServerNetworkingAuthentication {
    func headerAuthentication(forServerNetworking: ServerNetworking) -> [String:String]? {
        var result = [String:String]()
        if self.authTokens != nil {
            for (key, value) in self.authTokens! {
                result[key] = value
            }
        }
        
        result[ServerConstants.httpRequestDeviceUUID] = self.delegate.deviceUUID(forServerAPI: self).uuidString
        
        return result
    }
}
