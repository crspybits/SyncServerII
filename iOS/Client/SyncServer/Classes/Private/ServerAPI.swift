//
//  ServerAPI.swift
//  Pods
//
//  Created by Christopher Prince on 12/24/16.
//
//

import Foundation
import SMCoreLib

protocol ServerAPIDelegate : class {
    func deviceUUID(forServerAPI: ServerAPI) -> Foundation.UUID
    
#if DEBUG
    func doneUploadsRequestTestLockSync(forServerAPI: ServerAPI) -> TimeInterval?
#endif
}

class ServerAPI {
    // These need to be set by user of this class.
    var baseURL:String!
    weak var delegate:ServerAPIDelegate!
    
#if DEBUG
    private var _failNextEndpoint = false
    
    // Failure testing.
    var failNextEndpoint: Bool {
        // Returns the current value, and resets to false.
        get {
            let curr = _failNextEndpoint
            _failNextEndpoint = false
            return curr || failEndpoints
        }
        
        set {
            _failNextEndpoint = true
        }
    }
    
    // Fails endpoints until you set this to true.
    var failEndpoints = false
#endif
    
    fileprivate var authTokens:[String:String]?
    
    let httpUnauthorizedError = HTTPStatus.unauthorized.rawValue

    enum ServerAPIError : Error {
    case non200StatusCode(Int)
    case badStatusCode(Int)
    }
    
    // If this is nil, you must use the ServerNetworking authenticationDelegate to provide credentials. Direct use of authenticationDelegate is for internal testing.
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
    
    func checkForError(statusCode:Int?, error:Error?) -> Error? {
        // We don't necessarily want to treat an HTTPStatus.unauthorized as an error: It's a valid response when the user isn't present on the server.
        if statusCode == HTTPStatus.ok.rawValue || statusCode == HTTPStatus.unauthorized.rawValue || statusCode == nil  {
            return error
        }
        else {
            return ServerAPIError.non200StatusCode(statusCode!)
        }
    }
    
    // MARK: Health check
    
    func healthCheck(completion:((Error?)->(Void))?) {
        let endpoint = ServerEndpoints.healthCheck
        let url = URL(string: baseURL + endpoint.path)!
        
        sendRequestUsing(method: endpoint.method, toURL: url) { (response,  httpStatus, error) in
            completion?(self.checkForError(statusCode: httpStatus, error: error))
        }
    }

    // MARK: Authentication/user-sign in
    
    // Adds the user specified by the creds property (or authenticationDelegate in ServerNetworking if that is nil).
    public func addUser(completion:((Error?)->(Void))?) {
        let endpoint = ServerEndpoints.addUser
        let url = URL(string: baseURL + endpoint.path)!
        
        sendRequestUsing(method: endpoint.method,
            toURL: url) { (response,  httpStatus, error) in
            completion?(self.checkForError(statusCode: httpStatus, error: error))
        }
    }
    
    // Checks the creds of the user specified by the creds property (or authenticationDelegate in ServerNetworking if that is nil). Because this method uses an unauthorized (401) http status code to indicate that the user doesn't exist, it will not do retries in the case of an error.
    public func checkCreds(completion:((_ userExists:Bool?, Error?)->(Void))?) {
        let endpoint = ServerEndpoints.checkCreds
        let url = URL(string: baseURL + endpoint.path)!
        
        sendRequestUsing(method: endpoint.method, toURL: url, retryIfError: false) { (response, httpStatus, error) in
            
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
    
    func removeUser(retryIfError:Bool=true, completion:((Error?)->(Void))?) {
        let endpoint = ServerEndpoints.removeUser
        let url = URL(string: baseURL + endpoint.path)!
        
        sendRequestUsing(method: endpoint.method, toURL: url, retryIfError: retryIfError) {
            (response,  httpStatus, error) in
            completion?(self.checkForError(statusCode: httpStatus, error: error))
        }
    }
    
    // MARK: Files
    
    enum FileIndexError : Error {
    case fileIndexResponseConversionError
    case couldNotCreateFileIndexRequest
    }
        
    func fileIndex(completion:((_ fileIndex: [FileInfo]?, _ masterVersion:MasterVersionInt?, Error?)->(Void))?) {
    
        let endpoint = ServerEndpoints.fileIndex
        
        let url = URL(string: baseURL + endpoint.path)!
        
        sendRequestUsing(method: endpoint.method, toURL: url) { (response,  httpStatus, error) in
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
    
    struct File : Filenaming {
        let localURL:URL!
        let fileUUID:String!
        let mimeType:String!
        let cloudFolderName:String!
        let deviceUUID:String!
        let appMetaData:String?
        let fileVersion:FileVersionInt!
    }
    
    enum UploadFileError : Error {
    case couldNotCreateUploadFileRequest
    case couldNotReadUploadFile
    case noExpectedResultKey
    }
    
    enum UploadFileResult {
    case success(sizeInBytes:Int64)
    case serverMasterVersionUpdate(Int64)
    }
    
    func uploadFile(file:File, serverMasterVersion:MasterVersionInt, completion:((UploadFileResult?, Error?)->(Void))?) {
        let endpoint = ServerEndpoints.uploadFile

        Log.msg("ServerNetworking.session.authenticationDelegate2: \(ServerNetworking.session.authenticationDelegate)")
        
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
            let message = UploadFileError.couldNotReadUploadFile
            Log.error("\(message)")
            completion?(nil, message);
            return
        }
        
        let parameters = uploadRequest.urlParameters()!
        let url = URL(string: baseURL + endpoint.path + "/?" + parameters)!
        
        postUploadDataTo(url, dataToUpload: fileData) { (resultDict, httpStatus, error) in
        
            let resultError = self.checkForError(statusCode: httpStatus, error: error)

            if resultError == nil {
                if let size = resultDict?[UploadFileResponse.sizeKey] as? Int64 {
                    completion?(UploadFileResult.success(sizeInBytes:size), nil)
                }
                else if let versionUpdate = resultDict?[UploadFileResponse.masterVersionUpdateKey] as? Int64 {
                    let message = UploadFileResult.serverMasterVersionUpdate(versionUpdate)
                    Log.msg("\(message)")
                    completion?(message, nil)
                }
                else {
                    let message = UploadFileError.noExpectedResultKey
                    Log.error("\(message)")
                    completion?(nil, UploadFileError.noExpectedResultKey)
                }
            }
            else {
                Log.error("\(resultError!)")
                completion?(nil, resultError)
            }
        }
    }
    
    enum DoneUploadsError : Error {
    case noExpectedResultKey
    case couldNotCreateDoneUploadsRequest
    }
    
    enum DoneUploadsResult {
    case success(numberUploadsTransferred:Int64)
    case serverMasterVersionUpdate(Int64)
    }
    
    func doneUploads(serverMasterVersion:MasterVersionInt!, completion:((DoneUploadsResult?, Error?)->(Void))?) {
        let endpoint = ServerEndpoints.doneUploads
        
        var params = [String : Any]()
        params[DoneUploadsRequest.masterVersionKey] = serverMasterVersion
        
#if DEBUG
        if let testLockSync = delegate.doneUploadsRequestTestLockSync(forServerAPI: self) {
            params[DoneUploadsRequest.testLockSyncKey] = Int32(testLockSync)
        }
#endif
        
        guard let doneUploadsRequest = DoneUploadsRequest(json: params) else {
            completion?(nil, DoneUploadsError.couldNotCreateDoneUploadsRequest)
            return
        }

        let parameters = doneUploadsRequest.urlParameters()!
        let url = URL(string: baseURL + endpoint.path + "/?" + parameters)!

        sendRequestUsing(method: endpoint.method, toURL: url) { (response,  httpStatus, error) in
        
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
    
    struct DownloadedFile {
    let url: SMRelativeLocalURL
    let fileSizeBytes:Int64
    let appMetaData:String?
    }
    
    enum DownloadFileResult {
    case success(DownloadedFile)
    case serverMasterVersionUpdate(Int64)
    }
    
    enum DownloadFileError : Error {
    case couldNotCreateDownloadFileRequest
    case obtainedAppMetaDataButWasNotString
    case noExpectedResultKey
    case nilResponse
    case couldNotObtainHeaderParameters
    case resultURLObtainedWasNil
    }
    
    func downloadFile(file: Filenaming, serverMasterVersion:MasterVersionInt!, completion:((DownloadFileResult?, Error?)->(Void))?) {
        let endpoint = ServerEndpoints.downloadFile
        
        var params = [String : Any]()
        params[DownloadFileRequest.masterVersionKey] = serverMasterVersion
        params[DownloadFileRequest.fileUUIDKey] = file.fileUUID
        params[DownloadFileRequest.fileVersionKey] = file.fileVersion

        guard let downloadFileRequest = DownloadFileRequest(json: params) else {
            completion?(nil, DownloadFileError.couldNotCreateDownloadFileRequest)
            return
        }

        let parameters = downloadFileRequest.urlParameters()!
        let serverURL = URL(string: baseURL + endpoint.path + "/?" + parameters)!

        downloadFrom(serverURL, method: endpoint.method) { (resultURL, response, statusCode, error) in
        
            guard response != nil else {
                let resultError = error ?? DownloadFileError.nilResponse
                completion?(nil, resultError)
                return
            }
            
            let resultError = self.checkForError(statusCode: statusCode, error: error)

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
                        
                        let downloadedFile = DownloadedFile(url: resultURL!, fileSizeBytes: fileSizeBytes, appMetaData: appMetaDataString)
                        completion?(.success(downloadedFile), nil)
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
    
    enum GetUploadsError : Error {
    case getUploadsResponseConversionError
    case couldNotCreateFileIndexRequest
    }
        
    func getUploads(completion:((_ fileIndex: [FileInfo]?, Error?)->(Void))?) {
    
        let endpoint = ServerEndpoints.getUploads
        
        let url = URL(string: baseURL + endpoint.path)!
        
        sendRequestUsing(method: endpoint.method, toURL: url) { (response,  httpStatus, error) in
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
    
    enum UploadDeletionResult {
    case success
    case serverMasterVersionUpdate(Int64)
    }
    
    struct FileToDelete {
        let fileUUID:String!
        let fileVersion:FileVersionInt!
        
#if DEBUG
        var actualDeletion:Bool = false
#endif

        init(fileUUID:String, fileVersion:FileVersionInt) {
            self.fileUUID = fileUUID
            self.fileVersion = fileVersion
        }
    }
    
    enum UploadDeletionError : Error {
    case getUploadDeletionResponseConversionError
    }
    
    func uploadDeletion(file: FileToDelete, serverMasterVersion:MasterVersionInt!, completion:((UploadDeletionResult?, Error?)->(Void))?) {
        let endpoint = ServerEndpoints.uploadDeletion
        
        let url = URL(string: baseURL + endpoint.path)!
        
        var paramsForRequest:[String:Any] = [:]
        paramsForRequest[UploadDeletionRequest.fileUUIDKey] = file.fileUUID
        paramsForRequest[UploadDeletionRequest.fileVersionKey] = file.fileVersion
        paramsForRequest[UploadDeletionRequest.masterVersionKey] = serverMasterVersion
        
#if DEBUG
        if file.actualDeletion {
            paramsForRequest[UploadDeletionRequest.actualDeletionKey] = 1
        }
#endif
        
        let uploadDeletion = UploadDeletionRequest(json: paramsForRequest)!
        
        let parameters = uploadDeletion.urlParameters()!
        let serverURL = URL(string: baseURL + endpoint.path + "/?" + parameters)!
        
        sendRequestUsing(method: endpoint.method, toURL: serverURL) { (response,  httpStatus, error) in
            let resultError = self.checkForError(statusCode: httpStatus, error: error)
            
            if resultError == nil {
                if let uploadDeletionResponse = UploadDeletionResponse(json: response!) {
                    if let masterVersionUpdate = uploadDeletionResponse.masterVersionUpdate {
                        completion?(UploadDeletionResult.serverMasterVersionUpdate(masterVersionUpdate), nil)
                    }
                    else {
                        completion?(UploadDeletionResult.success, nil)
                    }
                }
                else {
                    completion?(nil, UploadDeletionError.getUploadDeletionResponseConversionError)
                }
            }
            else {
                completion?(nil, resultError)
            }
        }
    }
}

let maximumNumberRetries = 3

// MARK: Wrapper over ServerNetworking calls to provide for error retries and credentials refresh.
extension ServerAPI {
    func sendRequestUsing(method: ServerHTTPMethod, toURL serverURL: URL, retryIfError retry:Bool=true,
        completion:((_ serverResponse:[String:Any]?, _ statusCode:Int?, _ error:Error?)->())?) {
        
        var request:(()->())!
        var numberOfAttempts = 0
        
        func requestCompletion(_ serverResponse:[String:Any]?, _ statusCode:Int?, _ error:Error?) {
            if retry {
                retryIfError(error, statusCode:statusCode, numberOfAttempts: &numberOfAttempts, request: request) {
                    completion?(serverResponse, statusCode, error)
                }
            }
            else {
                completion?(serverResponse, statusCode, error)
            }
        }
        
        request = {
            ServerNetworking.session.sendRequestUsing(method: method, toURL: serverURL) { (serverResponse, statusCode, error) in
                if statusCode == self.httpUnauthorizedError && self.creds != nil {
                    self.creds!.refreshCredentials() { error in
                        // Only try refresh once!
                        if error == nil {
                            // Since we're only doing the refresh once, I'm not doing retries here.
                            ServerNetworking.session.sendRequestUsing(method: method, toURL: serverURL, completion: completion)
                        }
                        else {
                            requestCompletion(nil, nil, error)
                        }
                    }
                }
                else {
                    requestCompletion(serverResponse, statusCode, error)
                }
            }
        }
        
        request()
    }
    
    func postUploadDataTo(_ serverURL: URL, dataToUpload:Data, completion:((_ serverResponse:[String:Any]?, _ statusCode:Int?, _ error:Error?)->())?) {
        
        var request:(()->())!
        var numberOfAttempts = 0
        
        func requestCompletion(_ serverResponse:[String:Any]?, _ statusCode:Int?, _ error:Error?) {
            retryIfError(error, statusCode:statusCode, numberOfAttempts: &numberOfAttempts, request: request) {
                completion?(serverResponse, statusCode, error)
            }
        }
        
        request = {
            ServerNetworking.session.postUploadDataTo(serverURL, dataToUpload: dataToUpload) { (serverResponse, statusCode, error) in
                if statusCode == self.httpUnauthorizedError && self.creds != nil {
                    self.creds!.refreshCredentials() { error in
                        // Only try refresh once!
                        if error == nil {
                            ServerNetworking.session.postUploadDataTo(serverURL, dataToUpload: dataToUpload, completion:completion)
                        }
                        else {
                            requestCompletion(nil, nil, error)
                        }
                    }
                }
                else {
                    requestCompletion(serverResponse, statusCode, error)
                }
            }
        }
        
        request()
    }
    
    func downloadFrom(_ serverURL: URL, method: ServerHTTPMethod, completion:((SMRelativeLocalURL?, _ urlResponse:HTTPURLResponse?, _ statusCode:Int?, _ error:Error?)->())?) {
    
        var request:(()->())!
        var numberOfAttempts = 0
        
        func requestCompletion(_ localURL:SMRelativeLocalURL?, _ urlResponse:HTTPURLResponse?, _ statusCode:Int?, _ error:Error?) {
            retryIfError(error, statusCode:statusCode, numberOfAttempts: &numberOfAttempts, request: request) {
                completion?(localURL, urlResponse, statusCode, error)
            }
        }
        
        request = {
            ServerNetworking.session.downloadFrom(serverURL, method: method) { (localURL, urlResponse, statusCode, error) in
                if statusCode == self.httpUnauthorizedError && self.creds != nil {
                    self.creds!.refreshCredentials() { error in
                        // Only try refresh once!
                        if error == nil {
                            ServerNetworking.session.downloadFrom(serverURL, method: method, completion: completion)
                        }
                        else {
                            requestCompletion(nil, nil, nil, error)
                        }
                    }
                }
                else {
                    requestCompletion(localURL, urlResponse, statusCode, error)
                }
            }
        }
        
        request()
    }
    
    func retryIfError(_ error:Error?, statusCode:Int?, numberOfAttempts:inout Int, request:@escaping ()->(), completion:()->()) {
    
        let errorCheck = checkForError(statusCode:statusCode, error:error)
        if errorCheck == nil {
            completion()
        }
        else if numberOfAttempts <= maximumNumberRetries {
            numberOfAttempts += 1
            self.exponentialFallback(forAttempt: numberOfAttempts) {
                request()
            }
        } else {
            completion()
        }
    }
    
    // Returns a duration in seconds.
    func exponentialFallbackDuration(forAttempt numberTimesTried:Int) -> TimeInterval {
        let duration = TimeInterval(pow(Float(numberTimesTried), 2.0))
        Log.msg("Will try operation again in \(duration) seconds")
        return duration
    }

    // I'm making this available from SMServerNetworking because the concept of exponential fallback is at the networking level.
    func exponentialFallback(forAttempt numberTimesTried:Int, completion:@escaping ()->()) {
        let duration = exponentialFallbackDuration(forAttempt: numberTimesTried)

        TimedCallback.withDuration(Float(duration)) {
            completion()
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
        
#if DEBUG
        if failNextEndpoint {
            result[ServerConstants.httpRequestEndpointFailureTestKey] = "true"
        }
#endif
        
        return result
    }
}
