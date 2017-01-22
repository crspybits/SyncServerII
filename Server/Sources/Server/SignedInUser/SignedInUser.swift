//
//  SignedInUser.swift
//  Server
//
//  Created by Christopher Prince on 12/4/16.
//
//

import Foundation

public class SignedInUser {
    static let session = SignedInUser()
    private init() {
    }
    
    // Endpoints with authenticationLevel == .secondary have a current User.
    var current:User?
}
