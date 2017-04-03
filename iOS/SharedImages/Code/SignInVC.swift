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
        
        // TODO: *2* Signing out and then signing in as a different user will mess up this app. What we're really assuming is that the user may sign out, but will then again sign in as the same user. If the user signs in as a different user, we need to alert them that this is going to remove all local files. And, signing in again as the prior user will cause redownload of the prior files. This may be something we want to fix in the future: To enable the client to handle multiple users. This would require indexing the meta data by user.
        
        let googleSignInButton = SignIn.session.googleSignIn.signInButton(delegate: self)
        googleSignInButton.frameY = 100
        view.addSubview(googleSignInButton)
        googleSignInButton.centerHorizontallyInSuperview()
    }
}
