//
//  ViewController.swift
//  SyncServer
//
//  Created by Christopher Prince on 11/29/16.
//  Copyright © 2016 Spastic Muffin, LLC. All rights reserved.
//

import UIKit
import SMCoreLib
import AFNetworking
import SyncServer

fileprivate let HTTP_SUCCESS = 200

class ViewController: SMGoogleUserSignInViewController {
    var task:URLSessionDataTask!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        SignIn.session.googleSignIn.delegate = self
        
        let googleSignInButton = SignIn.session.googleSignIn.signInButton(delegate: self)
        googleSignInButton.frameOrigin = CGPoint(x: 50, y: 100)
        self.view.addSubview(googleSignInButton)
    }
}

extension ViewController : SignInDelegate {
    // MARK: SignInDelegate methods

    func userDidSignIn(signIn:UserSignIn, credentials:SignInCreds) {
        self.signIntoServer(creds: credentials as! GoogleSignInCreds) { error in
            if nil == error {
                Log.msg("Success signing in!")
            }
            else {
                Log.error("*** Error signing in: \(error)")
            }
        }
    }
    
    func userFailedSignIn(signIn:UserSignIn, error: Error) {
        Log.error("*** Error signing in: \(error)")
        ServerAPI.session.creds = nil
    }
    
    // Helper method
    
    func signIntoServer(creds:GoogleSignInCreds, completion:@escaping (Error?) ->()) {
        Log.msg("Google access token: \(creds.accessToken)")
        
        ServerAPI.session.creds = creds
        ServerAPI.session.addUser { error in
            if error != nil {
                Log.error("Error: \(error)")
                // So the UI doesn't show the user as being signed in-- which just looks odd given we had a failure of signing in with the server.
                SignIn.session.googleSignIn.signUserOut()
            }
            
            completion(error)
        }
        
        // TODO: *0* If we fail in this, fallback to checking if user exists. Or vice versa.
    }
}

