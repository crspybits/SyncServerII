//
//  SyncServerUser.swift
//  SyncServer
//
//  Created by Christopher Prince on 12/2/16.
//  Copyright © 2016 Spastic Muffin, LLC. All rights reserved.
//

import Foundation
import SMCoreLib

open class SignInCreds {
    public init() {
    }
    
    public var username:String?
    public var email:String?
    
    // Uses ServerConstants keys to provide creds values for HTTP headers.
    open func authDict() -> [String:String] {
        var result = [String:String]()
        result[ServerConstants.httpUsernameKey] = self.username
        result[ServerConstants.httpEmailKey] = self.email
        return result
    }
}

/*
public protocol SignInDelegate : class {
    func userDidSignIn(signIn:UserSignIn, credentials:SignInCreds)
    func userFailedSignIn(signIn:UserSignIn, error:Error)
}

public protocol UserSignIn {
    weak var delegate:SignInDelegate? {get set}
    func signUserOut()
}
*/

public class SyncServerUser {
    public static let session = SyncServerUser()

    // A distinct UUID for this user mobile device.
    // I'm going to persist this in the keychain not so much because it needs to be secure, but rather because it will survive app deletions/reinstallations.
    static let mobileDeviceUUID = SMPersistItemString(name: "SyncServerUser.mobileDeviceUUID", initialStringValue: "", persistType: .keyChain)
    
    private init() {
        // Check to see if the device has a UUID already.
        if SyncServerUser.mobileDeviceUUID.stringValue.characters.count == 0 {
            SyncServerUser.mobileDeviceUUID.stringValue = UUID.make()
        }
    }
    
    public func checkForExistingUser(creds: SignInCreds,
        completion:@escaping (_ foundUser: Bool?, Error?) ->()) {
        
        Log.msg("SignInCreds: \(creds)")
        
        ServerAPI.session.delegate = self
        ServerAPI.session.creds = creds
        
        ServerAPI.session.checkCreds { (success, error) in
            if success != nil && success! {
                Log.msg("Succesfully signed in.")
                completion(true, nil)
            }
            else {
                ServerAPI.session.creds = nil
                if error == nil {
                    Log.msg("Did not find user!")
                    completion(false, nil)
                }
                else {
                    Log.error("Had an error: \(error)")
                    completion(nil, error)
                }
            }
        }
    }
    
    public func addUser(creds: SignInCreds, completion:@escaping (Error?) ->()) {
        Log.msg("SignInCreds: \(creds)")

        ServerAPI.session.delegate = self
        ServerAPI.session.creds = creds
        
        ServerAPI.session.addUser { error in
            if error != nil {
                ServerAPI.session.creds = nil
                Log.error("Error: \(error)")
            }
            
            completion(error)
        }
    }
}

extension SyncServerUser : ServerAPIDelegate {
    func deviceUUID(forServerAPI: ServerAPI) -> Foundation.UUID {
        return Foundation.UUID(uuidString: SyncServerUser.mobileDeviceUUID.stringValue)!
    }
    
#if DEBUG
    func doneUploadsRequestTestLockSync() -> TimeInterval? {
        return nil
    }
#endif
}


