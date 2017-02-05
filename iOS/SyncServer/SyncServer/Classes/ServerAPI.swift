//
//  ServerAPI.swift
//  Pods
//
//  Created by Christopher Prince on 12/24/16.
//
//

import Foundation
import SMCoreLib

public class ServerAPI {
    // Needs to be set by user of this class.
    public var baseURL:String!
    
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
    
    public func fileIndex(completion:((Error?)->(Void))?) {
        let endpoint = ServerEndpoints.fileIndex
        let url = URL(string: baseURL + endpoint.path)!
        
        // TODO: Need to create the UUID only once for the device, and store in user defaults.
        
        let params = [FileIndexRequest.deviceUUIDKey : UUID().uuidString]
        
        ServerNetworking.session.sendRequestUsing(method: endpoint.method, toURL: url, withParameters: params) { (response:[String : AnyObject]?,  httpStatus:Int?, error:Error?) in
        
            completion?(error)
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
    
    public func uploadFile(file:File, serverMasterVersion:MasterVersionInt!, completion:((UploadFileResult?, Error?)->(Void))?) {
        let endpoint = ServerEndpoints.uploadFile
        
        // TODO: Need to create the UUID only once for the device, and store in user defaults.
        let deviceUUID = UUID().uuidString
        
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
        let parameters = uploadRequest.urlParameters()!
        
        guard let fileData = try? Data(contentsOf: file.localURL) else {
            completion?(nil, UploadFileError.couldNotReadUploadFile);
            return;
        }
        
        let url = URL(string: baseURL + endpoint.path + "/?" + parameters)!
        
        ServerNetworking.session.postUploadDataTo(url, dataToUpload: fileData) { (resultDict, error) in
            if error == nil {
                if resultDict![UploadFileResponse.sizeKey] != nil {
                    let size = resultDict![UploadFileResponse.sizeKey] as! Int64
                    completion?(UploadFileResult.success(sizeInBytes:size), nil)
                }
                else if resultDict![UploadFileResponse.masterVersionUpdateKey] != nil {
                    let versionUpdate = resultDict![UploadFileResponse.masterVersionUpdateKey] as! Int64
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
}

extension ServerAPI : ServerNetworkingAuthentication {
    func headerAuthentication(forServerNetworking: ServerNetworking) -> [String:String]? {
        return self.authTokens
    }
}
