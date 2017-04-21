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
    
    // Override this if your credentials scheme enables a refresh.
    open func refreshCredentials(completion: @escaping (Error?) ->()) {
    }
}

public class SyncServerUser {
    private var _creds:SignInCreds?
    fileprivate var creds:SignInCreds? {
        set {
            ServerAPI.session.creds = newValue
            _creds = newValue
        }
        
        get {
            return _creds
        }
    }
    
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
        self.creds = creds
        
        ServerAPI.session.checkCreds { (success, error) in
            var foundUserResult:Bool?
            var errorResult:Error?
            
            if success != nil && success! {
                Log.msg("Succesfully signed in.")
                foundUserResult = true
            }
            else {
                self.creds = nil
                if error == nil {
                    Log.msg("Did not find user!")
                    foundUserResult = false
                }
                else {
                    Log.error("Had an error: \(error)")
                    errorResult = error
                }
            }
            
            Thread.runSync(onMainThread: {
                completion(foundUserResult, errorResult)
            })
        }
    }
    
    public func addUser(creds: SignInCreds, completion:@escaping (Error?) ->()) {
        Log.msg("SignInCreds: \(creds)")

        ServerAPI.session.delegate = self
        self.creds = creds
        
        ServerAPI.session.addUser { error in
            if error != nil {
                self.creds = nil
                Log.error("Error: \(error)")
            }
            Thread.runSync(onMainThread: {
                completion(error)
            })
        }
    }
    
    public func createSharingInvitation(withPermission permission:SharingPermission, completion:((_ invitationCode:String?, Error?)->(Void))?) {

        ServerAPI.session.createSharingInvitation(withPermission: permission) { (sharingInvitationUUID, error) in
            Thread.runSync(onMainThread: {
                completion?(sharingInvitationUUID, error)
            })
        }
    }
    
    public func redeemSharingInvitation(creds: SignInCreds, invitationCode:String, completion:((Error?)->())?) {
        
        ServerAPI.session.delegate = self
        self.creds = creds
        
        ServerAPI.session.redeemSharingInvitation(sharingInvitationUUID: invitationCode) { error in
            Thread.runSync(onMainThread: {
                completion?(error)
            })
        }
    }
}

extension SyncServerUser : ServerAPIDelegate {
    func deviceUUID(forServerAPI: ServerAPI) -> Foundation.UUID {
        return Foundation.UUID(uuidString: SyncServerUser.mobileDeviceUUID.stringValue)!
    }
    
#if DEBUG
    func doneUploadsRequestTestLockSync(forServerAPI: ServerAPI) -> TimeInterval? {
        return nil
    }
#endif
}


