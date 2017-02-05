//
//  UserSignIn.swift
//  SyncServer
//
//  Created by Christopher Prince on 12/2/16.
//  Copyright © 2016 Spastic Muffin, LLC. All rights reserved.
//

import Foundation

open class SignInCreds {
    public init() {
    }
    
    public var username:String?
    public var email:String?
    
    // Uses ServerConstants keys to provide creds values.
    open func authDict() -> [String:String] {
        var result = [String:String]()
        result[ServerConstants.httpUsernameKey] = self.username
        result[ServerConstants.httpEmailKey] = self.email
        return result
    }
}

public protocol SignInDelegate : class {
    func userDidSignIn(signIn:UserSignIn, credentials:SignInCreds)
    func userFailedSignIn(signIn:UserSignIn, error:Error)
}

public protocol UserSignIn {
    weak var delegate:SignInDelegate? {get set}
    func signUserOut()
}

