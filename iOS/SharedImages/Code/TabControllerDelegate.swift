//
//  TabControllerDelegate.swift
//  SharedImages
//
//  Created by Christopher Prince on 3/12/17.
//  Copyright © 2017 Spastic Muffin, LLC. All rights reserved.
//

import Foundation
import UIKit

class TabControllerDelegate : NSObject, UITabBarControllerDelegate {
    func tabBarController(_ tabBarController: UITabBarController, shouldSelect viewController: UIViewController) -> Bool {

        if viewController.restorationIdentifier == "ImagesNavController" {
            return SignIn.session.googleSignIn.userIsSignedIn
        }
        
        return true
    }
}
