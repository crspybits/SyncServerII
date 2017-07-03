
//
//  GenericSignIn.swift
//  SyncServer
//
//  Created by Christopher Prince on 6/23/17.
//  Copyright © 2017 Christopher Prince. All rights reserved.
//

import Foundation

public protocol GenericCredentials {
    // A unique identifier for the user. E.g., for Google this is their `sub`.
    var userId:String {get}

    // This is sent to the server as a human-readable means to identify the user.
    var username:String {get}

    // A name suitable for identifying the user via the UI. If available this should be the users email. Otherwise, it could be the same as the username.
    var uiDisplayName:String {get}

    var httpRequestHeaders:[String:String] {get}

    // If your credentials scheme enables a refresh, i.e., on the credentials expiring.
    // If your credentials scheme doesn't have a refresh capability, then immediately call the callback with a non-nil Error.
    func refreshCredentials(completion: @escaping (Error?) ->())
}

public enum UserActionNeeded {
    case createSharingUser(invitationCode:String)
    case createOwningUser
    case signInExistingUser
    case none // e.g., error
}

public enum UserActionOccurred {
    case userSignedOut
    case userNotFoundOnSignInAttempt
    case existingUserSignedIn(SharingPermission?)
    case sharingUserCreated
    case owningUserCreated
}

public protocol GenericSignOutDelegate : class {
    func userWasSignedOut(signIn:GenericSignIn)
}

public protocol GenericSignInDelegate : class {
    func shouldDoUserAction(signIn:GenericSignIn) -> UserActionNeeded
    func userActionOccurred(action:UserActionOccurred, signIn:GenericSignIn)
}

public enum SignInState {
    case signInStarted
    case signedIn
    case signedOut
}

public protocol GenericSignInManagerDelegate : class {
    func signInStateChanged(to state: SignInState, for signIn:GenericSignIn)
}

public protocol GenericSignIn : class {
    // Delgate not dependent on the UI. Typically present through lifespan of app.
    var signOutDelegate:GenericSignOutDelegate? {get set}

    // Delegate dependent on the UI. Typically present through only part of lifespan of app.
    var delegate:GenericSignInDelegate? {get set}
    
    // Used exclusively by the SignInManager.
    var managerDelegate:GenericSignInManagerDelegate! {get set}
    
    func appLaunchSetup(silentSignIn: Bool)
    
    func application(_ application: UIApplication!, openURL url: URL!, sourceApplication: String!, annotation: AnyObject!) -> Bool

    // The UI element to use to allow signing in. A successful result will give a non-nil UI element.
    func getSignInButton(params:[String:Any]) -> UIView?

    var userIsSignedIn: Bool {get}

    // Non-nil if userIsSignedIn is true.
    var credentials:GenericCredentials? {get}

    func signUserOut()
}

