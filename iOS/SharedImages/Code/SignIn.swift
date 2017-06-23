//
//  SignIn.swift
//  SyncServer
//
//  Created by Christopher Prince on 12/2/16.
//  Copyright © 2016 Spastic Muffin, LLC. All rights reserved.
//

import Foundation
import SMCoreLib

class SignIn {
    let googleSignIn: SMGoogleUserSignIn!
    static let session = SignIn()
    
    // These must be stored in user defaults-- so that if they delete the app, we lose it, and can start again. Storing both the email and userId because the userId (at least for Google) is just a number and not intelligible in the UI.
    static var currentUserEmail = SMPersistItemString(name:"SignIn.currentUserEmail", initialStringValue:"",  persistType: .userDefaults)
    static var currentUserId = SMPersistItemString(name:"SignIn.currentUserId", initialStringValue:"",  persistType: .userDefaults)

    private init() {
        var serverClientId:String!
        var appClientId:String!
        
        let plist = try! PlistDictLoader(plistFileNameInBundle: Consts.serverPlistFile)
        
        if case .stringValue(let value) = try! plist.getRequired(varName: "GoogleClientId") {
            appClientId = value
        }
        
        if case .stringValue(let value) = try! plist.getRequired(varName: "GoogleServerClientId") {
            serverClientId = value
        }
    
        self.googleSignIn =  SMGoogleUserSignIn(serverClientId: serverClientId, appClientId: appClientId)
        self.googleSignIn.signOutDelegate = self
        self.googleSignIn.appLaunchSetup(silentSignIn: true)
    }
}

// I'm using this delegate to deal with this case: When we have an error refreshing credentials, and the SignInVC was not loaded, then we were not showing the user the sign in screen. They would otherwise be in a signed out state, but still be on the images screen.
extension SignIn : GoogleUserSignOutDelegate {
    func userWasSignedOut(googleUserSignIn:SMGoogleUserSignIn) {
        let appDelegate = UIApplication.shared.delegate as! AppDelegate
        appDelegate.selectTabInController(tab: .signIn)
    }
}
