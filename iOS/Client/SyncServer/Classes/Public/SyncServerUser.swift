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
    public var creds:SignInCreds? {
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
        
        ServerAPI.session.delegate = self
    }
    
    public enum CheckForExistingUserResult {
    case noUser
    case owningUser
    case sharingUser(sharingPermission:SharingPermission)
    }
    
    public func checkForExistingUser(creds: SignInCreds,
        completion:@escaping (_ result: CheckForExistingUserResult?, Error?) ->()) {
        
        Log.msg("SignInCreds: \(creds)")
        
        self.creds = creds
        
        ServerAPI.session.checkCreds { (checkCredsResult, error) in
            var checkForUserResult:CheckForExistingUserResult?
            var errorResult:Error? = error
            
            switch checkCredsResult {
            case .none:
                self.creds = nil
                if error == nil {
                    Log.msg("Did not find user!")
                    checkForUserResult = .noUser
                }
                else {
                    Log.error("Had an error: \(String(describing: error))")
                    errorResult = error
                }
            
            case .some(.noUser):
                checkForUserResult = .noUser
                
            case .some(.owningUser):
                checkForUserResult = .owningUser
                
            case .some(.sharingUser(let permission)):
                checkForUserResult = .sharingUser(sharingPermission: permission)
            }
            
            Thread.runSync(onMainThread: {
                completion(checkForUserResult, errorResult)
            })
        }
    }
    
    public func addUser(creds: SignInCreds, completion:@escaping (Error?) ->()) {
        Log.msg("SignInCreds: \(creds)")

        self.creds = creds
        
        ServerAPI.session.addUser { error in
            if error != nil {
                self.creds = nil
                Log.error("Error: \(String(describing: error))")
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


