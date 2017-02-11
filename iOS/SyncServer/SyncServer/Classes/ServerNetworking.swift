//
//  ServerNetworking.swift
//  SyncServer
//
//  Created by Christopher Prince on 11/29/15.
//  Copyright © 2015 Christopher Prince. All rights reserved.
//

// 11/29/15; I switched over to AFNetworking because with Alamofire uploading a file with parameters was too complicated.
// See http://stackoverflow.com/questions/26335630/bridging-issue-while-using-afnetworking-with-pods-in-a-swift-project for integrating AFNetworking and Swift.

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
        /*
        self.manager = AFHTTPSessionManager()
            // http://stackoverflow.com/questions/26604911/afnetworking-2-0-parameter-encoding
        self.manager.responseSerializer = AFJSONResponseSerializer()
    
        // This does appear necessary for requests going out to server to receive properly encoded JSON parameters on the server.
        self.manager.requestSerializer = AFJSONRequestSerializer()

        self.manager.requestSerializer.setValue("application/json", forHTTPHeaderField: "Content-Type")
        */
    }
    
    // fileprivate var uploadTask:URLSessionUploadTask?
    //private var downloadTask:NSURLSessionDownloadTask?
    //private var dataTask:NSURLSessionDataTask?
    
    func appLaunchSetup() {
        // To get "spinner" in status bar when ever we have network activity.
        // See http://cocoadocs.org/docsets/AFNetworking/2.0.0/Classes/AFNetworkActivityIndicatorManager.html
        AFNetworkActivityIndicatorManager.shared().isEnabled = true
    }

#if false
    // In the completion handler, if error != nil, there will be a non-nil serverResponse.
    func sendRequestUsing(method: ServerHTTPMethod, toURL serverURL: URL, withParameters parameters:[String:Any]? = nil,
        completion:((_ serverResponse:[String:AnyObject]?, _ statusCode:Int?, _ error:Error?)->())?) {
        /*  
        1) The http address here must *not* be localhost as we're addressing my Mac Laptop, where the Node.js server is running, and this app is running on my iPhone, a separate device.
        2) Using responseJSON is causing an error. i.e., response.result.error is non-nil. See http://stackoverflow.com/questions/32355850/alamofire-invalid-value-around-character-0
        *** BUT this was because the server was returning "Hello World", a non-json string!
        3) Have used https://forums.developer.apple.com/thread/3544 so I don't need SSL/https for now.
        4) The "encoding: .JSON" parameter seems needed so that I get nested dictionaries in the parameters (i.e., dictionaries as the values of keys) correctly coming across as json structures on the server. See also http://stackoverflow.com/questions/30394112/how-do-i-use-json-arrays-with-alamofire-parameters (This was with Alamofire)
        */

        Log.special("serverURL: \(serverURL)")
        
        var sendParameters = parameters
#if false
        if (SMTest.session.serverDebugTest != nil) {
            sendParameters[SMServerConstants.debugTestCaseKey] = SMTest.session.serverDebugTest
        }
#endif

        if !Network.connected() {
            completion?(nil, nil, SMError.Create("Network not connected."))
            return
        }
        
        let authDict = self.authenticationDelegate?.headerAuthentication(forServerNetworking: self)
        if authDict != nil {
            for (key, value) in authDict! {
                self.manager.requestSerializer.setValue(value, forHTTPHeaderField: key)
            }
        }
        
        // Without this, if the authenticationDelegate gets reset to nil, self.manager.requestSerializer will still have the prior authentication key/values
        func resetHeaderKeys() {
            if authDict != nil {
                for (key, _) in authDict! {
                    self.manager.requestSerializer.setValue(nil, forHTTPHeaderField: key)
                }
            }
        }

        func success(request:URLSessionDataTask, response:Any?) {
            resetHeaderKeys()
            let httpResponse = request.response as! HTTPURLResponse
            Log.msg("httpResponse.statusCode: \(httpResponse.statusCode)")
        
            if let responseDict = response as? [String:AnyObject] {
                Log.msg("AFNetworking Success: \(response)")
                completion?(responseDict, httpResponse.statusCode, nil)
            }
            else {
                completion?(nil, httpResponse.statusCode, SMError.Create("No dictionary given in response"))
            }
        }
        
        func failure(request:URLSessionDataTask?, error:Error) {
            resetHeaderKeys()
            let httpResponse = request?.response as? HTTPURLResponse
            Log.error("response.statusCode: \(httpResponse?.statusCode)")
            Log.error("**** AFNetworking FAILURE: \(error)")
            completion?(nil, httpResponse?.statusCode, error)
        }

        switch method {
        case .get:
            self.manager.get(serverURL.absoluteString, parameters: sendParameters, progress: nil,
                success: { (request:URLSessionDataTask, response:Any?) in
                    success(request:request, response:response)
                },
                failure: { (request:URLSessionDataTask?, error:Error) in
                    failure(request:request, error:error)
                })
            
        case .post:
            self.manager.post(serverURL.absoluteString, parameters: sendParameters, progress: nil,
                success: { (request:URLSessionDataTask, response:Any?) in
                    success(request:request, response:response)
                },
                failure: { (request:URLSessionDataTask?, error:Error) in
                    failure(request:request, error:error)
                })
        }
    }
#endif

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
        
        let sessionConfiguration = URLSessionConfiguration.default
        sessionConfiguration.httpAdditionalHeaders = self.authenticationDelegate?.headerAuthentication(forServerNetworking: self)
        
        // If needed, use a delegate here to track upload progress.
        let session = URLSession(configuration: sessionConfiguration)
    
        // Data uploading task. We could use NSURLSessionUploadTask instead of NSURLSessionDataTask if we needed to support uploads in the background
        
        var request = URLRequest(url: serverURL)
        request.httpMethod = "POST"
        request.httpBody = dataToUpload
        
        Log.special("serverURL: \(serverURL)")
        
        let uploadTask:URLSessionUploadTask = session.uploadTask(with: request, from: dataToUpload) { (data, urlResponse, error) in
            Log.special("request.url: \(request.url)")
            
            self.processResponse(data: data, urlResponse: urlResponse, error: error, completion: completion)
        }
        
        uploadTask.resume()
    }
    
    private func sendRequestTo(_ serverURL: URL, method: ServerHTTPMethod, dataToUpload:Data? = nil, completion:((_ serverResponse:[String:Any]?, _ statusCode:Int?, _ error:Error?)->())?) {
    
        let sessionConfiguration = URLSessionConfiguration.default
        sessionConfiguration.httpAdditionalHeaders = self.authenticationDelegate?.headerAuthentication(forServerNetworking: self)
        
        // If needed, use a delegate here to track upload progress.
        let session = URLSession(configuration: sessionConfiguration)
    
        // Data uploading task. We could use NSURLSessionUploadTask instead of NSURLSessionDataTask if we needed to support uploads in the background
        
        var request = URLRequest(url: serverURL)
        request.httpMethod = method.rawValue.uppercased()
        request.httpBody = dataToUpload
        
        Log.special("serverURL: \(serverURL)")
        
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

#if false
    // withParameters must have a non-nil key SMServerConstants.fileMIMEtypeKey
    func uploadFileTo(_ serverURL: URL, fileToUpload:URL, withParameters parameters:[String:AnyObject]?, completion:((_ serverResponse:[String:AnyObject]?, _ error:NSError?)->())?) {
        
        Log.special("serverURL: \(serverURL)")
        Log.special("fileToUpload: \(fileToUpload)")
        
        var sendParameters:[String:AnyObject]? = parameters
#if DEBUG
        if (SMTest.session.serverDebugTest != nil) {
            if parameters == nil {
                sendParameters = [String:AnyObject]()
            }
            
            sendParameters![SMServerConstants.debugTestCaseKey] = SMTest.session.serverDebugTest
        }
#endif

        if !Network.connected() {
            completion?(serverResponse: [SMServerConstants.resultCodeKey:SMServerConstants.rcNetworkFailure], error: Error.Create("Network not connected."))
            return
        }
        
        let mimeType = sendParameters![SMServerConstants.fileMIMEtypeKey]
        Assert.If(mimeType == nil, thenPrintThisString: "You must give a mime type!")
        
        var error:NSError? = nil

        // For the reason for this JSON serialization, see https://stackoverflow.com/questions/37449472/afnetworking-v3-1-0-multipartformrequestwithmethod-uploads-json-numeric-values-w/
        var jsonData:Data?
        var jsonString:String?
        
        do {
            try jsonData = JSONSerialization.data(withJSONObject: sendParameters!, options: JSONSerialization.WritingOptions(rawValue: 0))
        } catch (let error) {
            Assert.badMojo(alwaysPrintThisString: "Yikes: Error serializing to JSON data: \(error)")
        }
 
        do {
            try jsonString = String(data: jsonData!, encoding: String.Encoding.utf8)
        } catch (let error) {
            Assert.badMojo(alwaysPrintThisString: "Yikes: Error serializing to JSON string: \(error)")
        }
        
        // The server needs to pull SMServerConstants.serverParametersForFileUpload out of the request body, then convert the value to JSON
        //let serverParameters = [SMServerConstants.serverParametersForFileUpload : jsonData!]
        
        // http://stackoverflow.com/questions/34517582/how-can-i-prevent-modifications-of-a-png-file-uploaded-using-afnetworking-to-a-n
        // I have now set the COMPRESS_PNG_FILES Build Setting to NO to deal with this.
        
        let request = AFHTTPRequestSerializer().multipartFormRequest(withMethod: "POST", urlString: serverURL.absoluteString, parameters: nil, constructingBodyWith: { (formData: AFMultipartFormData) in
                // NOTE!!! the name: given here *must* match up with that used on the server in the "multer" single parameter.
                // Was getting an odd try/catch error here, so this is the reason for "try!"; see https://github.com/AFNetworking/AFNetworking/issues/3005
                // 12/12/15; I think this issue was because I wasn't doing the do/try/catch, however.
                do {
                    //try formData.appendPartWithFileURL(fileToUpload, name: SMServerConstants.fileUploadFieldName, fileName: "Kitty.png", mimeType: mimeType! as! String)
                    try formData.appendPartWithFileURL(fileToUpload, name: SMServerConstants.fileUploadFieldName)
                } catch let error {
                    let message = "Failed to appendPartWithFileURL: \(fileToUpload); error: \(error)!"
                    Log.error(message)
                    completion?(nil, Error.Create(message))
                }
            }, error: &error)
        
        if nil != error {
            completion?(nil, error)
            return
        }
        
        request.setValue(jsonString, forHTTPHeaderField: SMServerConstants.httpUploadParamHeader)
        Log.msg("httpUploadParamHeader: \(jsonString)")
        
        self.uploadTask = self.manager.uploadTask(withStreamedRequest: request as URLRequest, progress: { (progress:Progress) in
            },
            completionHandler: { (request: URLResponse, responseObject: AnyObject?, error: NSError?) in
                if (error == nil) {
                    if let responseDict = responseObject as? [String:AnyObject] {
                        Log.msg("AFNetworking Success: \(responseObject)")
                        completion?(serverResponse: responseDict, error: nil)
                    }
                    else {
                        let error = Error.Create("No dictionary given in response")
                        Log.error("**** AFNetworking FAILURE: \(error)")
                        completion?(serverResponse: nil, error: error)
                    }
                }
                else {
                    Log.error("**** AFNetworking FAILURE: \(error)")
                    completion?(serverResponse: nil, error: error)
                }
            })
        
        if nil == self.uploadTask {
            completion?(nil, SMError.Create("Could not start upload task"))
            return
        }
        
        self.uploadTask?.resume()
    }

    func downloadFileFrom(_ serverURL: URL, fileToDownload:URL, withParameters parameters:[String:AnyObject]?, completion:((_ serverResponse:[String:AnyObject]?, _ error:NSError?)->())?) {
        
        Log.special("serverURL: \(serverURL)")
        Log.special("fileToDownload: \(fileToDownload)")
        
        var sendParameters:[String:AnyObject]? = parameters
        
#if DEBUG
        if (SMTest.session.serverDebugTest != nil) {
            if parameters == nil {
                sendParameters = [String:AnyObject]()
            }
            
            sendParameters![SMServerConstants.debugTestCaseKey] = SMTest.session.serverDebugTest
        }
#endif

        if !Network.connected() {
            completion?(serverResponse: [SMServerConstants.resultCodeKey:SMServerConstants.rcNetworkFailure], error: Error.Create("Network not connected."))
            return
        }
        
        //self.download1(serverURL)
        //self.download2(serverURL)
        //self.download3(serverURL, parameters:sendParameters)
        
        let sessionConfig = URLSessionConfiguration.default
        // TODO: When do we need a delegate/delegateQueue here?
        let session = URLSession(configuration: sessionConfig, delegate: nil, delegateQueue: nil)
        let request = NSMutableURLRequest(url: serverURL)
        request.httpMethod = "POST"
        
        if sendParameters != nil {
            var jsonData:Data?
            
            do {
                try jsonData = JSONSerialization.data(withJSONObject: sendParameters!, options: JSONSerialization.WritingOptions(rawValue: 0))
            } catch (let error) {
                completion?(serverResponse: [SMServerConstants.resultCodeKey:SMServerConstants.rcInternalError], error: Error.Create("Could not serialize JSON parameters: \(error)"))
                return
            }
            
            request.httpBody = jsonData
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            request.setValue("\(jsonData!.count)", forHTTPHeaderField: "Content-Length")
        }
        
        let task = session.downloadTask(with: request, completionHandler: { (urlOfDownload:URL?, response:URLResponse?, error:NSError?)  in
             if (error == nil) {
                // Success
                if let httpResponse = response as? HTTPURLResponse {
                    let statusCode = httpResponse.statusCode
                    if statusCode != 200 {
                        completion?(serverResponse: [SMServerConstants.resultCodeKey:SMServerConstants.rcOperationFailed], error: Error.Create("Status code= \(statusCode) was not 200!"))
                        return
                    }
                    
                    if urlOfDownload == nil {
                        completion?(serverResponse: [SMServerConstants.resultCodeKey:SMServerConstants.rcOperationFailed], error: Error.Create("Got nil downloaded file URL!"))
                        return
                    }
                    
                    Log.msg("urlOfDownload: \(urlOfDownload)")
                    
                    // I've not been able to figure out how to get a file downloaded along with parameters (e.g., return result from the server), so I'm using a custom HTTP header to get result parameters back from the server.
                    
                    Log.msg("httpResponse.allHeaderFields: \(httpResponse.allHeaderFields)")
                    let downloadParams = httpResponse.allHeaderFields[SMServerConstants.httpDownloadParamHeader]
                    Log.msg("downloadParams: \(downloadParams)")
                    
                    if let downloadParamsString = downloadParams as? String {
                        let downloadParamsDict = self.convertJSONStringToDictionary(downloadParamsString)

                        Log.msg("downloadParamsDict: \(downloadParamsDict)")
                        if downloadParamsDict == nil {
                            completion?(serverResponse: [SMServerConstants.resultCodeKey:SMServerConstants.rcOperationFailed], error: Error.Create("Did not get parameters from server!"))
                        }
                        else {
                            // We can still get to this point without a downloaded file. Oddly enough the urlOfDownload might not be nil, but we won't have a downloaded file. Our downloadParamsDict will indicate the error, and the caller will have to figure things out.
                            
                            // urlOfDownload is the temporary file location given by downloadTaskWithRequest. Not sure how long it persists. Move it to our own temporary location. We're more assured of that lasting.
                            
                            // Make sure destination file (fileToDownload) isn't there first. Get an error with moveItemAtURL if it is.
                            
                            let mgr = FileManager.default
                            
                            // I don't really care about an error here, attempting to removeItemAtURL. i.e., it could be an error just because the file isn't there-- which would be the usual case.
                            do {
                                try mgr.removeItem(at: fileToDownload)
                            } catch (let err) {
                                Log.error("removeItemAtURL: \(err)")
                            }
                            
                            var error:NSError?
                            do {
                                try mgr.moveItem(at: urlOfDownload!, to: fileToDownload)
                            } catch (let err) {
                                let errorString = "moveItemAtURL: \(err)"
                                error = Error.Create(errorString)
                                Log.error(errorString)
                            }
                            
                            // serverResponse will be non-nil if we throw an errow in the file move, but the caller should check the error so, should be OK.
                            completion?(serverResponse: downloadParamsDict, error: error)
                        }
                    }
                    else {
                        completion?(serverResponse: [SMServerConstants.resultCodeKey:SMServerConstants.rcOperationFailed], error: Error.Create("Did not get downloadParamsString from server!"))
                    }
                }
                else {
                    // Could not get NSHTTPURLResponse
                    completion?(serverResponse: [SMServerConstants.resultCodeKey:SMServerConstants.rcOperationFailed], error: Error.Create("Did not get NSHTTPURLResponse from server!"))
                }
            }
            else {
                // Failure
                completion?(serverResponse: nil, error: error)
            }
        }) 
        
        task.resume()
    }
#endif

/*
    func download0() {
        //let configuration = NSURLSessionConfiguration.defaultSessionConfiguration()
        //let manager = AFURLSessionManager(sessionConfiguration: configuration)
        var error:NSError? = nil

        // Not getting anything received on server.
        // let request = AFHTTPRequestSerializer().multipartFormRequestWithMethod("POST", URLString: serverURL.absoluteString, parameters: sendParameters, constructingBodyWithBlock: nil, error: &error)
        
        // Not getting anything received on server.
        // let request = AFHTTPRequestSerializer().requestWithMethod("POST", URLString: serverURL.absoluteString, parameters: parameters, error: &error)
        
        let request = NSMutableURLRequest(URL: serverURL)
        request.HTTPMethod = "POST"
        
        if nil != error {
            completion?(serverResponse: nil, error: error)
            return
        }

        // Doesn't show up on server.
        /*
        self.dataTask = self.manager.dataTaskWithRequest(request,
            uploadProgress: { (uploadProgress:NSProgress) -> Void in
                
            }, downloadProgress: { (downloadProgress:NSProgress) -> Void in
                
            }) { (response:NSURLResponse, responseObject:AnyObject?, error:NSError?) -> Void in
            }
        */

        self.downloadTask = self.manager.downloadTaskWithRequest(request,
            progress: { (progress:NSProgress) in
            
            }, destination: { (targetPath:NSURL, response:NSURLResponse) -> NSURL in
                // destination: A block object to be executed in order to determine the destination of the downloaded file. This block takes two arguments, the target path & the server response, and returns the desired file URL of the resulting download. The temporary file used during the download will be automatically deleted after being moved to the returned URL.
                Log.msg("destination: targetPath: \(targetPath)")
                Log.msg("destination: response: \(response)")
                return fileToDownload
            }, completionHandler: { (response:NSURLResponse, url:NSURL?, error:NSError?) in
                // completionHandler A block to be executed when a task finishes. This block has no return value and takes three arguments: the server response, the path of the downloaded file, and the error describing the network or parsing error that occurred, if any.
                Log.msg("response: \(response)")
                Log.msg("url: \(url)")
                completion?(serverResponse: nil, error: error)
            })
    }
*/

/*
    // This gets through to the server, but, of course, I'm not getting the credentials parameters.
    func download1(URL: NSURL) {
        let sessionConfig = NSURLSessionConfiguration.defaultSessionConfiguration()
        let session = NSURLSession(configuration: sessionConfig, delegate: nil, delegateQueue: nil)
        let request = NSMutableURLRequest(URL: URL)
        request.HTTPMethod = "POST"
        
        let task = session.dataTaskWithRequest(request, completionHandler: { (data: NSData?, response: NSURLResponse?, error: NSError?) in
            if (error == nil) {
                // Success
                let statusCode = (response as! NSHTTPURLResponse).statusCode
                Log.msg("statusCode: \(statusCode)")
                Log.msg("response: \(response)")
                Log.msg("data: \(data)")
                // This is your file-variable:
                // data
            }
            else {
                // Failure
                Log.msg("Failure: \(error)")
            }
        })
        
        task.resume()
    }

    // This also gets through to the server, but, of course, I'm not getting the credentials parameters.
    func download2(URL: NSURL) {
        let sessionConfig = NSURLSessionConfiguration.defaultSessionConfiguration()
        let session = NSURLSession(configuration: sessionConfig, delegate: nil, delegateQueue: nil)
        let request = NSMutableURLRequest(URL: URL)
        request.HTTPMethod = "POST"
        
        let task = session.downloadTaskWithRequest(request) { (urlOfDownload:NSURL?, response:NSURLResponse?, error:NSError?)  in
             if (error == nil) {
                // Success
                let statusCode = (response as! NSHTTPURLResponse).statusCode
                Log.msg("statusCode: \(statusCode)")
                Log.msg("response: \(response)")
                Log.msg("urlOfDownload: \(urlOfDownload)")
            }
            else {
                // Failure
                Log.msg("Failure: \(error)")
            }
        }
        
        task.resume()
    }
    
    func download3(_ URL: Foundation.URL, parameters:[String:AnyObject]?) {
        let sessionConfig = URLSessionConfiguration.default
        let session = URLSession(configuration: sessionConfig, delegate: nil, delegateQueue: nil)
        let request = NSMutableURLRequest(url: URL)
        request.httpMethod = "POST"
        
        if parameters != nil {
            var jsonData:Data?
            
            do {
                try jsonData = JSONSerialization.data(withJSONObject: parameters!, options: JSONSerialization.WritingOptions(rawValue: 0))
            } catch (let error) {
                Log.msg("error: \(error)")
                return
            }
            
            request.httpBody = jsonData
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            request.setValue("\(jsonData!.count)", forHTTPHeaderField: "Content-Length")
        }
        
        let task = session.downloadTask(with: request, completionHandler: { (urlOfDownload:Foundation.URL?, response:URLResponse?, error:NSError?)  in
             if (error == nil) {
                // Success
                let httpResponse = response as! HTTPURLResponse
                
                let statusCode = httpResponse.statusCode
                // statusCode should be 200-- check it.
                
                Log.msg("statusCode: \(statusCode)")
                Log.msg("urlOfDownload: \(urlOfDownload)")
                Log.msg("httpResponse.allHeaderFields: \(httpResponse.allHeaderFields)")
                let downloadParams = httpResponse.allHeaderFields[SMServerConstants.httpDownloadParamHeader]
                Log.msg("downloadParams: \(downloadParams)")
                Log.msg("downloadParams type: \(type(of: downloadParams))")
                if let downloadParamsString = downloadParams as? String {
                    let downloadParamsDict = self.convertJSONStringToDictionary(downloadParamsString)
                    Log.msg("downloadParamsDict: \(downloadParamsDict)")
                    if downloadParamsDict == nil {
                    }
                    else {
                    
                    }
                }
            }
            else {
                // Failure
                Log.msg("Failure: \(error)")
            }
        }) 
        
        task.resume()
    }
    
    // See http://stackoverflow.com/questions/30480672/how-to-convert-a-json-string-to-a-dictionary
    fileprivate func convertJSONStringToDictionary(_ text: String) -> [String:AnyObject]? {
        if let data = text.data(using: String.Encoding.utf8) {
            do {
                let json = try JSONSerialization.jsonObject(with: data, options: .mutableContainers) as? [String:AnyObject]
                return json
            } catch {
                Log.error("Something went wrong")
            }
        }
        return nil
    }
    */
    
/*
NSURLSessionConfiguration *configuration = [NSURLSessionConfiguration defaultSessionConfiguration];
AFURLSessionManager *manager = [[AFURLSessionManager alloc] initWithSessionConfiguration:configuration];

NSURL *URL = [NSURL URLWithString:@"http://example.com/download.zip"];
NSURLRequest *request = [NSURLRequest requestWithURL:URL];

NSURLSessionDownloadTask *downloadTask = [manager downloadTaskWithRequest:request progress:nil destination:^NSURL *(NSURL *targetPath, NSURLResponse *response) {
    NSURL *documentsDirectoryURL = [[NSFileManager defaultManager] URLForDirectory:NSDocumentDirectory inDomain:NSUserDomainMask appropriateForURL:nil create:NO error:nil];
    return [documentsDirectoryURL URLByAppendingPathComponent:[response suggestedFilename]];
} completionHandler:^(NSURLResponse *response, NSURL *filePath, NSError *error) {
    NSLog(@"File downloaded to: %@", filePath);
}];
[downloadTask resume];
*/
    
    
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
