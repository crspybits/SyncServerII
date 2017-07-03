//
//  SMFacebookUserSignIn.swift
//  SyncServer
//
//  Created by Christopher Prince on 6/11/16.
//  Copyright © 2016 Spastic Muffin, LLC. All rights reserved.
//

// Enables you to sign in as a Facebook user to (a) create a new sharing user (must have an invitation from another SyncServer user), or (b) sign in as an existing sharing user.

import Foundation
import SyncServer
import SMCoreLib
import FBSDKLoginKit

// I tried this initially as a way to find friends, but that didn't work
// Does *not* return friends in the way that would be useful to us here.
/*
// See https://developers.facebook.com/docs/graph-api/reference/user/friends/
FBSDKGraphRequest(graphPath: "me/friends", parameters: ["fields" : "data"]).startWithCompletionHandler { (connection:FBSDKGraphRequestConnection!, result: AnyObject!, error: NSError!) in
    Log.msg("result: \(result); error: \(error)")
}*/

open class SMFacebookUserSignIn : SMUserSignInAccount {
    fileprivate static let _fbUserName = SMPersistItemString(name: "SMFacebookUserSignIn.fbUserName", initialStringValue: "", persistType: .UserDefaults)
    fileprivate static let _currentOwningUserId = SMPersistItemString(name: "SMFacebookUserSignIn.currentOwningUserId", initialStringValue: "", persistType: .UserDefaults)
    
    fileprivate var fbUserName:String? {
        get {
            return SMFacebookUserSignIn._fbUserName.stringValue == "" ? nil : SMFacebookUserSignIn._fbUserName.stringValue
        }
        set {
            SMFacebookUserSignIn._fbUserName.stringValue =
                newValue == nil ? "" : newValue!
        }
    }
    
    // The shared data that we're using right now.
    fileprivate var currentOwningUserId:String? {
        get {
            return SMFacebookUserSignIn._currentOwningUserId.stringValue == "" ? nil : SMFacebookUserSignIn._currentOwningUserId.stringValue
        }
        set {
            SMFacebookUserSignIn._currentOwningUserId.stringValue =
                newValue == nil ? "" : newValue!
        }
    }

    override open static var displayNameS: String? {
        get {
            return SMServerConstants.accountTypeFacebook
        }
    }
    
    override open var displayNameI: String? {
        get {
            return SMFacebookUserSignIn.displayNameS
        }
    }
    
    override public init() {
    }
    
    override open func syncServerAppLaunchSetup(silentSignIn: Bool, launchOptions:[AnyHashable: Any]?) {
    
        // TODO: What can be done for a silent sign-in? Perhaps pass a silent parameter to finishSignIn.
        
        // FBSDKLoginManager public class func renewSystemCredentials(handler: ((ACAccountCredentialRenewResult, NSError!) -> Void)!)
        
        // http://stackoverflow.com/questions/32950937/fbsdkaccesstoken-currentaccesstoken-nil-after-quitting-app
        FBSDKApplicationDelegate.sharedInstance().application(UIApplication.sharedApplication(), didFinishLaunchingWithOptions: launchOptions)
        
        Log.msg("FBSDKAccessToken.currentAccessToken(): \(FBSDKAccessToken.currentAccessToken())")
        
        if self.syncServerUserIsSignedIn {
            self.finishSignIn()
        }
    }
    
    override open func application(_ application: UIApplication!, openURL url: URL!, sourceApplication: String!, annotation: AnyObject!) -> Bool {
        return FBSDKApplicationDelegate.sharedInstance().application(application, openURL: url, sourceApplication: sourceApplication, annotation: annotation)
    }
    
    override open var syncServerUserIsSignedIn: Bool {
        get {
            return FBSDKAccessToken.currentAccessToken() != nil
        }
    }
    
    override open var syncServerSignedInUser:SMUserCredentials? {
        get {
            if self.syncServerUserIsSignedIn {
                return .Facebook(userType: .SharingUser(owningUserId: self.currentOwningUserId), accessToken: FBSDKAccessToken.currentAccessToken().tokenString, userId: FBSDKAccessToken.currentAccessToken().userID, userName: self.fbUserName)
            }
            else {
                return nil
            }
        }
    }
    
    override open func syncServerSignOutUser() {
        self.reallyLogOut()
    }
    
    override open func syncServerRefreshUserCredentials() {
    }
    
    open func signInButton() -> UIButton {
        let fbLoginButton = FBSDKLoginButton()
        // fbLoginButton.readPermissions =  ["public_profile", "email", "user_friends"]
        fbLoginButton.readPermissions =  ["email"]
        fbLoginButton.delegate = self
            
        let longPress = UILongPressGestureRecognizer(target: self, action: #selector(longPressAction))
        fbLoginButton.addGestureRecognizer(longPress)
        
        return fbLoginButton
    }
    
    @objc fileprivate func longPressAction() {
        if FBSDKAccessToken.currentAccessToken() != nil {
            self.reallyLogOut()
        }
    }
}

extension SMFacebookUserSignIn : FBSDKLoginButtonDelegate {
    public func loginButton(_ loginButton: FBSDKLoginButton!, didCompleteWithResult result: FBSDKLoginManagerLoginResult!, error: NSError!) {
    
        Log.msg("result: \(result); error: \(error)")
        
        if !result.isCancelled && error == nil {
            self.finishSignIn()
        }
    }

    public func loginButtonDidLogOut(_ loginButton: FBSDKLoginButton!) {
        self.completeReallyLogOut()
    }
    
    fileprivate func finishSignIn() {
        Log.msg("FBSDKAccessToken.currentAccessToken().userID: \(FBSDKAccessToken.currentAccessToken().userID)")
        
        // Adapted from http://stackoverflow.com/questions/29323244/facebook-ios-sdk-4-0how-to-get-user-email-address-from-fbsdkprofile
        let parameters = ["fields" : "email, id, name"]
        FBSDKGraphRequest(graphPath: "me", parameters: parameters).startWithCompletionHandler { (connection:FBSDKGraphRequestConnection!, result: AnyObject!, error: NSError!) in
            Log.msg("result: \(result); error: \(error)")
            
            if nil == error {
                if let resultDict = result as? [String:AnyObject] {
                    // I'm going to prefer the email address, if we get it, just because it's more distinctive than the name.
                    if resultDict["email"] != nil {
                        self.fbUserName = resultDict["email"] as? String
                    }
                    else {
                        self.fbUserName = resultDict["name"] as? String
                    }
                }
            }
            
            Log.msg("self.currentOwningUserId: \(self.currentOwningUserId)")
            
            let syncServerFacebookUser = SMUserCredentials.Facebook(userType: .SharingUser(owningUserId: self.currentOwningUserId), accessToken: FBSDKAccessToken.currentAccessToken().tokenString, userId: FBSDKAccessToken.currentAccessToken().userID, userName: self.fbUserName)
            
            // We are not going to allow the user to create a new sharing user without an invitation code. There just doesn't seem any point: They wouldn't have any access capabilities. So, if we don't have an invitation code, check to see if this user is already on the system.
            let sharingInvitationCode = self.delegate.smUserSignIn(getSharingInvitationCodeForUserSignIn: self)
            
            if sharingInvitationCode == nil {
                self.signInWithNoInvitation(facebookUser: syncServerFacebookUser)
            }
            else {
                // Going to redeem the invitation even if we get an error checking for email/name (username). The username is optional.
                
                // redeemSharingInvitation creates a new user if needed at the same time as redeeming invitation.
                // Success on redeeming does the sign callback in process.
                /*
                SMSyncServerUser.session.redeemSharingInvitation(invitationCode: sharingInvitationCode!, userCreds: syncServerFacebookUser) { (linkedOwningUserId, error) in
                    if error == nil {
                        // Now, when the Facebook creds get sent to the server, they'll have this linkedOwningUserId.
                        self.currentOwningUserId = linkedOwningUserId
                        Log.msg("redeemSharingInvitation self.currentOwningUserId: \(self.currentOwningUserId); linkedOwningUserId: \(linkedOwningUserId)")
                        
                        self.delegate.smUserSignIn(userJustSignedIn: self)
                    
                        // If we could not redeem the invitation (couldNotRedeemSharingInvitation is true), we want to set the invitation to nil-- it was bad. If we could redeem it, we also want to set it to nil-- no point in trying to redeem it again.
                        self.delegate.smUserSignIn(resetSharingInvitationCodeForUserSignIn: self)
                    }
                    else if error != nil {
                        // TODO: Give them a UI error message.
                        // Hmmm. We have an odd state here. If it was a new user, we created the user, but we couldn't redeem the invitation. What to do??
                        Log.error("Failed redeeming invitation.")
                        self.reallyLogOut()
                    }
                }*/
            }
        }
    }
    
    fileprivate func signInWithNoInvitation(facebookUser:SMUserCredentials) {
        if self.currentOwningUserId == nil {
            // No owning user id; need to select which one we're going to use.
            /*
            SMSyncServerUser.session.getLinkedAccountsForSharingUser(facebookUser) { (linkedAccounts, error) in
                if error == nil {
                    self.delegate.smUserSignIn(userSignIn: self, linkedAccountsForSharingUser: linkedAccounts!, selectLinkedAccount: { (internalUserId) in
                        self.currentOwningUserId = internalUserId
                        self.signInWithOwningUserId(facebookUser: facebookUser)
                    })
                }
                else {
                    Log.error("Failed getting linked accounts.")
                    self.reallyLogOut()
                }
            }*/
        }
        else {
            self.signInWithOwningUserId(facebookUser: facebookUser)
        }
    }
    
    fileprivate func signInWithOwningUserId(facebookUser:SMUserCredentials) {
        SMSyncServerUser.session.checkForExistingUser(
            facebookUser, completion: { error in
            
            if error == nil {
                self.delegate.smUserSignIn(userJustSignedIn: self)
            }
            else {
                // TODO: This does not necessarily the user is not on the system. E.g., on a server crash or a network failure, we'll also get here. Need to check an error return code from the server.
                // TODO: Give them an error message. Tell them they need an invitation from user on the system first.
                Log.error("User not on the system: Need an invitation!")
                self.reallyLogOut()
            }
        })
    }
    
    // It seems really hard to fully logout!!! The following helps.
    fileprivate func reallyLogOut() {
        let deletepermission = FBSDKGraphRequest(graphPath: "me/permissions/", parameters: nil, HTTPMethod: "DELETE")
        deletepermission.startWithCompletionHandler({ (connection, result, error) in
            print("the delete permission is \(result)")
            FBSDKLoginManager().logOut()
            self.completeReallyLogOut()
        })
    }
    
    fileprivate func completeReallyLogOut() {
        self.delegate.smUserSignIn(userJustSignedOut: self)
        
        // So that the next time we sign in, we get a choice of which owningUserId's we'll use if there is more than one.
        self.currentOwningUserId = nil
    }
}

