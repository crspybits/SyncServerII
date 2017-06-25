
//
//  SignInManager.swift
//  SyncServer
//
//  Created by Christopher Prince on 6/23/17.
//  Copyright © 2017 Christopher Prince. All rights reserved.
//

import Foundation

class SignInManager {
    static let session = SignInManager()
    
    private init() {
    }
    
    // Based on the currently active signin method, this will call the corresponding method on that class.
    func application(_ application: UIApplication!, openURL url: URL!, sourceApplication: String!, annotation: AnyObject!) -> Bool {
        assert(false)
        return true
    }
}

