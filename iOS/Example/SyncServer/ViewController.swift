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

class ViewController: SMGoogleUserSignInViewController {
    var googleSignInButton:UIView!
    
    override func viewDidLoad() {
        super.viewDidLoad()
                
        googleSignInButton = SignIn.session.googleSignIn.signInButton(delegate: self)
        googleSignInButton.frameY = 100
        view.addSubview(googleSignInButton)
        googleSignInButton.centerHorizontallyInSuperview()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
    }
}



