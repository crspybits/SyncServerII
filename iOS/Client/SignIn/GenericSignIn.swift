
//
//  GenericSignIn.swift
//  SyncServer
//
//  Created by Christopher Prince on 6/23/17.
//  Copyright © 2017 Christopher Prince. All rights reserved.
//

import Foundation
import SyncServer

protocol UserIdentifiers {
var username:String! {get}
var email:String? {get}
}

protocol GenericSignIn {
func appLaunchSetup(silentSignIn: Bool)
func application(_ application: UIApplication!, openURL url: URL!, sourceApplication: String!, annotation: AnyObject!) -> Bool

var httpRequestHeaders:[String:String] {get}
var userIdentifiers:UserIdentifiers {get}

var userIsSignedIn: Bool {get}
func signUserOut()

func getSignInButton() -> UIView

}

