//
//  ServerAPI+Retries.swift
//  Pods
//
//  Created by Christopher Prince on 6/17/17.
//
//

import Foundation
import SMCoreLib

private class RequestWithRetries {
    let maximumNumberRetries = 3
    
    let creds:SignInCreds?
    let updateCreds:((_ creds:SignInCreds?)->())
    let checkForError:(_ statusCode:Int?, _ error:Error?) -> Error?
    let desiredEvents:EventDesired!
    weak var delegate:SyncServerDelegate!
    
    private var triedToRefreshCreds = false
    private var numberTries = 0
    private var retryIfError:Bool

    var request:(()->())!
    var completionHandler:((_ error:Error?)->())!
    
    init(retryIfError:Bool = true, creds:SignInCreds?, desiredEvents:EventDesired, delegate:SyncServerDelegate!, updateCreds:@escaping (_ creds:SignInCreds?)->(), checkForError:@escaping (_ statusCode:Int?, _ error:Error?) -> Error?) {
        self.creds = creds
        self.updateCreds = updateCreds
        self.checkForError = checkForError
        self.retryIfError = retryIfError
        self.desiredEvents = desiredEvents
        self.delegate = delegate
    }
    
    deinit {
        print("deinit: RequestWithRetries")
    }
    
    // Make sure self.creds is non-nil before you call this!
    private func refreshCredentials(completion: @escaping (Error?) ->()) {
        EventDesired.reportEvent(.refreshingCredentials, mask: self.desiredEvents, delegate: self.delegate)
        self.creds!.refreshCredentials { error in
            if error == nil {
                self.updateCreds(self.creds)
            }
            completion(error)
        }
    }
    
    // Returns a duration in seconds.
    func exponentialFallbackDuration(forAttempt numberTimesTried:Int) -> TimeInterval {
        let duration = TimeInterval(pow(Float(numberTimesTried), 2.0))
        Log.msg("Will try operation again in \(duration) seconds")
        return duration
    }

    func exponentialFallback(forAttempt numberTimesTried:Int, completion:@escaping ()->()) {
        let duration = exponentialFallbackDuration(forAttempt: numberTimesTried)

        TimedCallback.withDuration(Float(duration)) {
            completion()
        }
    }
    
    private func completion(_ error:Error?) {
        completionHandler(error)
        
        // Get rid of circular reference so `RequestWithRetries` instance can be deallocated.
        completionHandler = nil
        request = nil
    }

    func retryCheck(statusCode:Int?, error:Error?) {
        numberTries += 1
        let errorCheck = checkForError(statusCode, error)
        
        if errorCheck == nil || numberTries >= maximumNumberRetries || !retryIfError {
            completion(errorCheck)
        }
        else if statusCode == HTTPStatus.unauthorized.rawValue {
            if triedToRefreshCreds || creds == nil {
                // unauthorized, but we're not refreshing. Cowardly give up.
                completion(error)
            }
            else {
                triedToRefreshCreds = true
                
                self.refreshCredentials() {[unowned self] error in
                    if error == nil {
                        // Success on refresh-- try request again.
                        // Not using `exponentialFallback` because we know that the issue arose due to an authorization error.
                        self.start()
                    }
                    else {
                        // Failed on refreshing creds-- not much point in going on.
                        self.completion(error)
                    }
                }
            }
        }
        else {
            // We got an error, but it wasn't an authorization problem.
            // Let's make another try after waiting for a while.
            exponentialFallback(forAttempt: numberTries) {
                self.start()
            }
        }
    }
    
    func start() {
        request()
    }
}

// MARK: Wrapper over ServerNetworking calls to provide for error retries and credentials refresh.
extension ServerAPI {
    func sendRequestUsing(method: ServerHTTPMethod, toURL serverURL: URL, timeoutIntervalForRequest:TimeInterval? = nil, retryIfError retry:Bool=true, completion:((_ serverResponse:[String:Any]?, _ statusCode:Int?, _ error:Error?)->())?) {
        
        let rwr = RequestWithRetries(retryIfError: retry, creds:creds, desiredEvents:desiredEvents, delegate:syncServerDelegate, updateCreds: updateCreds, checkForError:checkForError)
        rwr.request = {
            ServerNetworking.session.sendRequestUsing(method: method, toURL: serverURL, timeoutIntervalForRequest:timeoutIntervalForRequest) { (serverResponse, statusCode, error) in
                
                rwr.completionHandler = { error in
                    completion?(serverResponse, statusCode, error)
                }
                rwr.retryCheck(statusCode: statusCode, error: error)
            }
        }
        rwr.start()
    }
    
    func postUploadDataTo(_ serverURL: URL, dataToUpload:Data, completion:((_ serverResponse:[String:Any]?, _ statusCode:Int?, _ error:Error?)->())?) {
        
        let rwr = RequestWithRetries(creds:creds, desiredEvents:desiredEvents, delegate:syncServerDelegate, updateCreds: updateCreds, checkForError:checkForError)
        rwr.request = {
            ServerNetworking.session.postUploadDataTo(serverURL, dataToUpload: dataToUpload) { (serverResponse, statusCode, error) in
                
                rwr.completionHandler = { error in
                    completion?(serverResponse, statusCode, error)
                }
                rwr.retryCheck(statusCode: statusCode, error: error)
            }
        }
        rwr.start()
    }
    
    func downloadFrom(_ serverURL: URL, method: ServerHTTPMethod, completion:((SMRelativeLocalURL?, _ urlResponse:HTTPURLResponse?, _ statusCode:Int?, _ error:Error?)->())?) {
        
        let rwr = RequestWithRetries(creds:creds, desiredEvents:desiredEvents, delegate:syncServerDelegate, updateCreds: updateCreds, checkForError:checkForError)
        rwr.request = {
            ServerNetworking.session.downloadFrom(serverURL, method: method) { (localURL, urlResponse, statusCode, error) in
                
                rwr.completionHandler = { error in
                    completion?(localURL, urlResponse, statusCode, error)
                }
                rwr.retryCheck(statusCode: statusCode, error: error)
            }
        }
        rwr.start()
    }
}
