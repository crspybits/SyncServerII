//
//  SignInVC.swift
//  SharedImages
//
//  Created by Christopher Prince on 3/12/17.
//  Copyright © 2017 Spastic Muffin, LLC. All rights reserved.
//

import Foundation
import UIKit
import SMCoreLib

class SignInVC : SMGoogleUserSignInViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
                
        let googleSignInButton = SignIn.session.googleSignIn.signInButton(delegate: self)
        googleSignInButton.frameY = 100
        view.addSubview(googleSignInButton)
        googleSignInButton.centerHorizontallyInSuperview()
    }
}
