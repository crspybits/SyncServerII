
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
    static var currentSignIn = SMPersistItemString(name:"SignInManager.currentSignIn", initialStringValue:"",  persistType: .userDefaults)

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
                SignInManager.currentSignIn.stringValue = stringNameForSignIn(currentSignIn!)
            }
        }
    }
    
    private func stringNameForSignIn(_ signIn: GenericSignIn) -> String {
        // This gives "GenericSignIn"
        // String(describing: type(of: currentSignIn!))
        
        let mirror = Mirror(reflecting: signIn)
        return "\(mirror.subjectType)"
    }
    
    // A shorthand-- because it's often used.
    public var userIsSignIn:Bool {
        return currentSignIn?.userIsSignedIn ?? false
    }
    
    // At launch, you must set up all the SignIn's that you'll be presenting to the user. This will call their `appLaunchSetup` method.
    public func addSignIn(_ signIn:GenericSignIn) {
        // Make sure we don't already have an instance of this signIn
        let name = stringNameForSignIn(signIn)
        let result = alternativeSignIns.filter({stringNameForSignIn($0) == name})
        assert(result.count == 0)
        
        alternativeSignIns.append(signIn)
        signIn.managerDelegate = self
        let silentSignIn = SignInManager.currentSignIn.stringValue == name
        signIn.appLaunchSetup(silentSignIn: silentSignIn)
    }
    
    // Based on the currently active signin method, this will call the corresponding method on that class.
    public func application(_ application: UIApplication!, openURL url: URL!, sourceApplication: String!, annotation: AnyObject!) -> Bool {
        
        for signIn in alternativeSignIns {
            if SignInManager.currentSignIn.stringValue == stringNameForSignIn(signIn) {
                return signIn.application(application, openURL: url, sourceApplication: sourceApplication, annotation: annotation)
            }
        }
        
        assert(false)
        
        return false
    }
}

extension SignInManager : GenericSignInManagerDelegate {
    public func signInStateChanged(to state: SignInState, for signIn:GenericSignIn) {
        switch state {
        case .signInStarted:
            // Must not have any other signin's active when attempting to sign in.
            assert(currentSignIn == nil)
            currentSignIn = signIn
            
        case .signedIn:
            break
            
        case .signedOut:
            currentSignIn = nil
        }
    }
}

