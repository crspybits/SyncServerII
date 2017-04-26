//
//  ViewController.swift
//  SyncServer
//
//  Created by Christopher Prince on 11/29/16.
//  Copyright © 2016 Spastic Muffin, LLC. All rights reserved.
//

import UIKit
import SMCoreLib
import SyncServer
import SevenSwitch

class ViewController: SMGoogleUserSignInViewController {
    var googleSignInButton:UIView!
    fileprivate var signinTypeSwitch:SevenSwitch!

    override func viewDidLoad() {
        super.viewDidLoad()
                
        googleSignInButton = SignIn.session.googleSignIn.signInButton(delegate: self)
        googleSignInButton.frameY = 100
        view.addSubview(googleSignInButton)
        googleSignInButton.centerHorizontallyInSuperview()
        
        SignIn.session.googleSignIn.delegate = self
        
        signinTypeSwitch = SevenSwitch()
        signinTypeSwitch.offLabel.text = "Existing user"
        signinTypeSwitch.offLabel.textColor = UIColor.black
        signinTypeSwitch.onLabel.text = "New user"
        signinTypeSwitch.onLabel.textColor = UIColor.black
        signinTypeSwitch.frameY = googleSignInButton.frameMaxY + 30
        signinTypeSwitch.frameWidth = 120
        signinTypeSwitch.inactiveColor =  UIColor(red: 0.5, green: 0.5, blue: 0.5, alpha: 1)
        signinTypeSwitch.onTintColor = UIColor(red: 16.0/255.0, green: 125.0/255.0, blue: 247.0/255.0, alpha: 1)
        view.addSubview(signinTypeSwitch)
        signinTypeSwitch.centerHorizontallyInSuperview()
        
        setSignInTypeState()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
    }
    
    func setSignInTypeState() {
        signinTypeSwitch?.isHidden = SignIn.session.googleSignIn.userIsSignedIn
    }
}

extension ViewController : SMGoogleUserSignInDelegate {
    func shouldDoUserAction(creds:GoogleSignInCreds) -> UserActionNeeded {
        var result:UserActionNeeded
        
        if signinTypeSwitch.isOn() {
            result = .createOwningUser
        }
        else {
            result = .signInExistingUser
        }
        
        return result
    }
    
    func userActionOccurred(action:UserActionOccurred, googleUserSignIn:SMGoogleUserSignIn) {
        switch action {
        case .userSignedOut:
            break
            
        case .userNotFoundOnSignInAttempt:
            Log.error("User not found on sign in attempt")
            
        case .existingUserSignedIn(_):
            break
            
        case .owningUserCreated:
            break
            
        case .sharingUserCreated:
            break
        }
        
        setSignInTypeState()
    }
}

