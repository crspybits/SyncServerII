//
//  ServerNetworking.swift
//  SyncServer
//
//  Created by Christopher Prince on 11/29/15.
//  Copyright © 2015 Christopher Prince. All rights reserved.
//

import Foundation
import AFNetworking
import SMCoreLib

protocol ServerNetworkingAuthentication : class {
    // Key/value pairs to be added to the outgoing HTTP header for authentication
    func headerAuthentication(forServerNetworking: ServerNetworking) -> [String:String]?
}

class ServerNetworking {
    //fileprivate let manager: AFHTTPSessionManager!
    static let session = ServerNetworking()
    weak var authenticationDelegate:ServerNetworkingAuthentication?
    
    fileprivate init() {
    }
    
    func appLaunchSetup() {
        // To get "spinner" in status bar when ever we have network activity.
        // See http://cocoadocs.org/docsets/AFNetworking/2.0.0/Classes/AFNetworkActivityIndicatorManager.html
        
        // TODO: *3* I think this isn't working any more-- I'm not using AFNetworking. How can I have a networking spinner in the status bar now?
        AFNetworkActivityIndicatorManager.shared().isEnabled = true
    }

    enum ServerNetworkingError : Error {
    case noNetworkError
    }
    
    func sendRequestUsing(method: ServerHTTPMethod, toURL serverURL: URL,
        completion:((_ serverResponse:[String:Any]?, _ statusCode:Int?, _ error:Error?)->())?) {
        
        sendRequestTo(serverURL, method: method) { (serverResponse, statusCode, error) in
            completion?(serverResponse, statusCode, error)
        }
    }
    
    enum PostUploadDataToError : Error {
    case ErrorConvertingServerResponseToJsonDict
    case CouldNotGetHTTPURLResponse
    }
    
    // Data is sent in the body via a POST request (not multipart).
    func postUploadDataTo(_ serverURL: URL, dataToUpload:Data, completion:((_ serverResponse:[String:Any]?, _ statusCode:Int?, _ error:Error?)->())?) {

        guard Network.session().connected() else {
            completion?(nil, nil, ServerNetworkingError.noNetworkError)
            return
        }
        
        let sessionConfiguration = URLSessionConfiguration.default
        sessionConfiguration.httpAdditionalHeaders = self.authenticationDelegate?.headerAuthentication(forServerNetworking: self)
        
        // COULD DO: Use a delegate here to track upload progress.
        let session = URLSession(configuration: sessionConfiguration)
    
        // COULD DO: Data uploading task. We could use NSURLSessionUploadTask instead of NSURLSessionDataTask if we needed to support uploads in the background
        
        var request = URLRequest(url: serverURL)
        request.httpMethod = "POST"
        request.httpBody = dataToUpload
        
        Log.msg("postUploadDataTo: serverURL: \(serverURL)")
        
        let uploadTask:URLSessionUploadTask = session.uploadTask(with: request, from: dataToUpload) { (data, urlResponse, error) in
            Log.msg("request.url: \(request.url)")
            
            self.processResponse(data: data, urlResponse: urlResponse, error: error, completion: completion)
        }
        
        uploadTask.resume()
    }
    
    enum DownloadFromError : Error {
    case couldNotGetHTTPURLResponse
    case didNotGetURL
    case couldNotMoveFile
    case couldNotCreateNewFile
    }
    
    func downloadFrom(_ serverURL: URL, method: ServerHTTPMethod, completion:((SMRelativeLocalURL?, _ serverResponse:HTTPURLResponse?, _ statusCode:Int?, _ error:Error?)->())?) {

        guard Network.session().connected() else {
            completion?(nil, nil, nil, ServerNetworkingError.noNetworkError)
            return
        }
        
        let sessionConfiguration = URLSessionConfiguration.default
        sessionConfiguration.httpAdditionalHeaders = self.authenticationDelegate?.headerAuthentication(forServerNetworking: self)
        
        let session = URLSession(configuration: sessionConfiguration)

        var request = URLRequest(url: serverURL)
        request.httpMethod = method.rawValue.uppercased()
        
        Log.msg("downloadFrom: serverURL: \(serverURL)")
        
        let downloadTask:URLSessionDownloadTask = session.downloadTask(with: request) { (url, urlResponse, error) in
        
            if error == nil {
                // With an HTTP or HTTPS request, we get HTTPURLResponse back. See https://developer.apple.com/reference/foundation/urlsession/1407613-datatask
                guard let response = urlResponse as? HTTPURLResponse else {
                    completion?(nil, nil, nil, DownloadFromError.couldNotGetHTTPURLResponse)
                    return
                }
                
                guard url != nil else {
                    completion?(nil, nil, response.statusCode, DownloadFromError.didNotGetURL)
                    return
                }
                
                // Transfer the temporary file to a more permanent location.
                if let newTempURL = FilesMisc.createTemporaryRelativeFile() {
                    do {
                        try FileManager.default.replaceItemAt(newTempURL as URL, withItemAt: url!)                        
                    }
                    catch (let error) {
                        Log.error("Could not move file: \(error)")
                        completion?(nil, nil, response.statusCode, DownloadFromError.couldNotMoveFile)
                        return
                    }
                    
                    completion?(newTempURL, response, response.statusCode, nil)
                }
                else {
                    completion?(nil, nil, response.statusCode, DownloadFromError.couldNotCreateNewFile)
                }
            }
            else {
                completion?(nil, nil, nil, error)
            }
        }

        downloadTask.resume()
    }
    
    private func sendRequestTo(_ serverURL: URL, method: ServerHTTPMethod, dataToUpload:Data? = nil, completion:((_ serverResponse:[String:Any]?, _ statusCode:Int?, _ error:Error?)->())?) {
    
        guard Network.session().connected() else {
            completion?(nil, nil, ServerNetworkingError.noNetworkError)
            return
        }
    
        let sessionConfiguration = URLSessionConfiguration.default
        sessionConfiguration.httpAdditionalHeaders = self.authenticationDelegate?.headerAuthentication(forServerNetworking: self)
        
        // If needed, use a delegate here to track upload progress.
        let session = URLSession(configuration: sessionConfiguration)
    
        // Data uploading task. We could use NSURLSessionUploadTask instead of NSURLSessionDataTask if we needed to support uploads in the background
        
        var request = URLRequest(url: serverURL)
        request.httpMethod = method.rawValue.uppercased()
        request.httpBody = dataToUpload
        
        Log.msg("sendRequestTo: serverURL: \(serverURL)")
        
        let uploadTask:URLSessionDataTask = session.dataTask(with: request) { (data, urlResponse, error) in
            self.processResponse(data: data, urlResponse: urlResponse, error: error, completion: completion)
        }
        
        uploadTask.resume()
    }
    
    private func processResponse(data:Data?, urlResponse:URLResponse?, error: Error?, completion:((_ serverResponse:[String:Any]?, _ statusCode:Int?, _ error:Error?)->())?) {
        if error == nil {
            // With an HTTP or HTTPS request, we get HTTPURLResponse back. See https://developer.apple.com/reference/foundation/urlsession/1407613-datatask
            guard let response = urlResponse as? HTTPURLResponse else {
                completion?(nil, nil, PostUploadDataToError.CouldNotGetHTTPURLResponse)
                return
            }
            
            var json:Any?
            do {
                try json = JSONSerialization.jsonObject(with: data!, options: JSONSerialization.ReadingOptions(rawValue: UInt(0)))
            } catch (let error) {
                Log.error("Error in JSON conversion: \(error)")
                completion?(nil, response.statusCode, error)
                return
            }
            
            guard let jsonDict = json as? [String: Any] else {
                completion?(nil, response.statusCode, PostUploadDataToError.ErrorConvertingServerResponseToJsonDict)
                return
            }
            
            Log.msg("No errors on upload: jsonDict: \(jsonDict)")
            completion?(jsonDict, response.statusCode, nil)
        }
        else {
            completion?(nil, nil, error)
        }
    }
}

extension ServerNetworking /* Extras */ {
    // Returns a duration in seconds.
    fileprivate class func exponentialFallbackDuration(forAttempt numberTimesTried:Int) -> Float {
        let duration:Float = pow(Float(numberTimesTried), 2.0)
        Log.msg("Will try operation again in \(duration) seconds")
        return duration
    }

    // I'm making this available from SMServerNetworking because the concept of exponential fallback is at the networking level.
    class func exponentialFallback(forAttempt numberTimesTried:Int, completion:@escaping ()->()) {
        let duration = ServerNetworking.exponentialFallbackDuration(forAttempt: numberTimesTried)

        TimedCallback.withDuration(duration) {
            completion()
        }
    }
}
