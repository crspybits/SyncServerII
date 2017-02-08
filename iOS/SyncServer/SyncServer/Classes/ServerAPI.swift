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

public extension ServerAPIDelegate {
    func doneUploadsRequestTestLockSync() -> TimeInterval? {
        return nil
    }
}

public class ServerAPI {
    // These need to be set by user of this class.
    public var baseURL:String!
    public weak var delegate:ServerAPIDelegate!
    
    fileprivate var authTokens:[String:String]?
    
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

    public func healthCheck(completion:((Error?)->(Void))?) {
        let endpoint = ServerEndpoints.healthCheck
        let url = URL(string: baseURL + endpoint.path)!
        
        ServerNetworking.session.sendRequestUsing(method: endpoint.method, toURL: url) { (response:[String : AnyObject]?,  httpStatus:Int?, error:Error?) in
            completion?(error)
        }
    }

    // MARK: Authentication/user-sign in
    
    // Adds the user specified by the creds property (or authenticationDelegate in ServerNetworking if that is nil).
    public func addUser(completion:((Error?)->(Void))?) {
        let endpoint = ServerEndpoints.addUser
        let url = URL(string: baseURL + endpoint.path)!
        
        ServerNetworking.session.sendRequestUsing(method: endpoint.method,
            toURL: url) { (response:[String : AnyObject]?,  httpStatus:Int?, error:Error?) in
            completion?(error)
        }
    }
    
    public func checkCreds(completion:((_ userExists:Bool?, Error?)->(Void))?) {
        let endpoint = ServerEndpoints.checkCreds
        let url = URL(string: baseURL + endpoint.path)!
        
        ServerNetworking.session.sendRequestUsing(method: endpoint.method,
            toURL: url) { (response:[String : AnyObject]?, httpStatus:Int?, error:Error?) in
            
            var userExists:Bool?
            if httpStatus == HTTPStatus.ok.rawValue {
                userExists = true
            }
            else if httpStatus == HTTPStatus.unauthorized.rawValue {
                userExists = false
            }
            
            if userExists == nil {
                assert(error != nil)
                completion?(nil, error)
            }
            else {
                completion?(userExists, nil)
            }
        }
    }
    
    public func removeUser(completion:((Error?)->(Void))?) {
        let endpoint = ServerEndpoints.removeUser
        let url = URL(string: baseURL + endpoint.path)!
        
        ServerNetworking.session.sendRequestUsing(method: endpoint.method, toURL: url) { (response:[String : AnyObject]?,  httpStatus:Int?, error:Error?) in
            completion?(error)
        }
    }
    
    // MARK: Files
    
    public enum FileIndexError : Error {
    case fileIndexResponseConversionError
    case couldNotCreateFileIndexRequest
    }
        
    public func fileIndex(completion:((_ fileIndex: [FileInfo]?, _ masterVersion:MasterVersionInt?, Error?)->(Void))?) {
    
        let endpoint = ServerEndpoints.fileIndex
        let deviceUUID = delegate.deviceUUID(forServerAPI: self).uuidString
        let params = [FileIndexRequest.deviceUUIDKey : deviceUUID]
        
        guard let fileIndexRequest = FileIndexRequest(json: params) else {
            completion?(nil, nil, FileIndexError.couldNotCreateFileIndexRequest);
            return;
        }
        
        let url = URL(string: baseURL + endpoint.path + "/?" + fileIndexRequest.urlParameters()!)!
        
        ServerNetworking.session.sendRequestUsing(method: endpoint.method, toURL: url) { (response:[String : AnyObject]?,  httpStatus:Int?, error:Error?) in
            if error == nil {
                if let fileIndexResponse = FileIndexResponse(json: response!) {
                    completion?(fileIndexResponse.fileIndex, fileIndexResponse.masterVersion, nil)
                }
                else {
                    completion?(nil, nil, FileIndexError.fileIndexResponseConversionError)
                }
            }
            else {
                completion?(nil, nil, error)
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

        let deviceUUID = delegate.deviceUUID(forServerAPI: self).uuidString

        let params:[String : Any] = [
            UploadFileRequest.fileUUIDKey: file.fileUUID,
            UploadFileRequest.mimeTypeKey: file.mimeType,
            UploadFileRequest.cloudFolderNameKey: file.cloudFolderName,
            UploadFileRequest.deviceUUIDKey: deviceUUID,
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
        
        ServerNetworking.session.postUploadDataTo(url, dataToUpload: fileData) { (resultDict, error) in
            if error == nil {
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
                completion?(nil, error)
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
        params[DoneUploadsRequest.deviceUUIDKey] = deviceUUID
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

        ServerNetworking.session.sendRequestUsing(method: endpoint.method, toURL: url) { (response:[String : AnyObject]?,  httpStatus:Int?, error:Error?) in
        
            if error == nil {
                if let numberUploads = response?[DoneUploadsResponse.numberUploadsTransferredKey] as? Int64 {
                    completion?(DoneUploadsResult.success(numberUploadsTransferred:numberUploads), nil)
                }
                else if let masterVersionUpdate = response?[DoneUploadsResponse.masterVersionUpdateKey] as? Int64 {
                    completion?(DoneUploadsResult.serverMasterVersionUpdate(masterVersionUpdate), nil)
                }
                else {
                    completion?(nil, DoneUploadsError.noExpectedResultKey)
                }
            }
            else {
                completion?(nil, error)
            }
        }
    }
}

extension ServerAPI : ServerNetworkingAuthentication {
    func headerAuthentication(forServerNetworking: ServerNetworking) -> [String:String]? {
        return self.authTokens
    }
}
