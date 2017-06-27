
//
//  SignInManager.swift
//  SyncServer
//
//  Created by Christopher Prince on 6/23/17.
//  Copyright © 2017 Christopher Prince. All rights reserved.
//

import Foundation
import SMCoreLib

public class SignInManager {
    // These must be stored in user defaults-- so that if they delete the app, we lose it, and can start again. Storing both the currentUIDisplayName and userId because the userId (at least for Google) is just a number and not intelligible in the UI.
    public static var currentUIDisplayName = SMPersistItemString(name:"SignInManager.currentUIDisplayName", initialStringValue:"",  persistType: .userDefaults)
    public static var currentUserId = SMPersistItemString(name:"SignInManager.currentUserId", initialStringValue:"",  persistType: .userDefaults)
    
    // The class name of the current GenericSignIn
    public static var currentSignIn = SMPersistItemString(name:"SignInManager.currentSignIn", initialStringValue:"",  persistType: .userDefaults)

    public static let session = SignInManager()
    
    private init() {
    }
    
    private var alternativeSignIns = [GenericSignIn]()
    
    // Set this to establish the current SignIn mechanism in use in the app.
    public var currentSignIn:GenericSignIn? {
        didSet {
            if currentSignIn == nil {
                SignInManager.currentSignIn.stringValue = ""
            }
            else {
                SignInManager.currentSignIn.stringValue = String(describing: type(of: currentSignIn))
            }
        }
    }
    
    // A shorthand-- because it's often used.
    public var userIsSignIn:Bool {
        return currentSignIn?.userIsSignedIn ?? false
    }
    
    // At launch, you must set up all the SignIn's that you'll be presenting to the user. This will call their `appLaunchSetup` method.
    public func addSignIn(_ signIn:GenericSignIn) {
        assert(false)
    }
    
    // Based on the currently active signin method, this will call the corresponding method on that class.
    public func application(_ application: UIApplication!, openURL url: URL!, sourceApplication: String!, annotation: AnyObject!) -> Bool {
        assert(false)
        return true
    }
}

