//
//  TabControllerDelegate.swift
//  SharedImages
//
//  Created by Christopher Prince on 3/12/17.
//  Copyright © 2017 Spastic Muffin, LLC. All rights reserved.
//

import Foundation
import UIKit

protocol TabControllerNavigation {
func tabBarViewControllerWasSelected()
}

class TabControllerDelegate : NSObject, UITabBarControllerDelegate {
    func tabBarController(_ tabBarController: UITabBarController, shouldSelect viewController: UIViewController) -> Bool {

        // Only allow a transition to the Images screen if the user is signed in.
        if viewController.restorationIdentifier == "ImagesNavController" {
            return SignIn.session.googleSignIn.userIsSignedIn
        }
        
        return true
    }
    
    func tabBarController(_ tabBarController: UITabBarController, didSelect viewController: UIViewController) {
        // Assumes each tab VC is nested in a nav controller
        if let nav = viewController as? UINavigationController,
            let topVC = nav.topViewController as? TabControllerNavigation {
            topVC.tabBarViewControllerWasSelected()
        }
    }
}

