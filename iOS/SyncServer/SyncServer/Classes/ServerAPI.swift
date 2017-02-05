//
//  ServerAPI.swift
//  Pods
//
//  Created by Christopher Prince on 12/24/16.
//
//

import Foundation

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
        let url = URL(string: baseURL + ServerEndpoints.healthCheck.path)!
        
        ServerNetworking.session.sendRequestUsing(method: ServerEndpoints.healthCheck.method, toURL: url) { (response:[String : AnyObject]?,  httpStatus:Int?, error:Error?) in
            completion?(error)
        }
    }

    // MARK: Authentication/user-sign in
    
    // Adds the user specified by the creds property (or authenticationDelegate in ServerNetworking if that is nil).
    public func addUser(completion:((Error?)->(Void))?) {
        let url = URL(string: baseURL + ServerEndpoints.addUser.path)!
        
        ServerNetworking.session.sendRequestUsing(method: ServerEndpoints.addUser.method,
            toURL: url) { (response:[String : AnyObject]?,  httpStatus:Int?, error:Error?) in
            completion?(error)
        }
    }
    
    public func checkCreds(completion:((_ userExists:Bool?, Error?)->(Void))?) {
        let url = URL(string: baseURL + ServerEndpoints.checkCreds.path)!
        
        ServerNetworking.session.sendRequestUsing(method: ServerEndpoints.checkCreds.method,
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
        let url = URL(string: baseURL + ServerEndpoints.removeUser.path)!
        
        ServerNetworking.session.sendRequestUsing(method: ServerEndpoints.removeUser.method, toURL: url) { (response:[String : AnyObject]?,  httpStatus:Int?, error:Error?) in
            completion?(error)
        }
    }
}

extension ServerAPI : ServerNetworkingAuthentication {
    func headerAuthentication(forServerNetworking: ServerNetworking) -> [String:String]? {
        return self.authTokens
    }
}
