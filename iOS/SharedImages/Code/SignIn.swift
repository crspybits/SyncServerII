//
//  SignIn.swift
//  SyncServer
//
//  Created by Christopher Prince on 12/2/16.
//  Copyright © 2016 Spastic Muffin, LLC. All rights reserved.
//

import Foundation
import SMCoreLib

class SignIn {
    let googleSignIn: SMGoogleUserSignIn!
    static let session = SignIn()
    
    init() {
        var serverClientId:String!
        var appClientId:String!
        
        let plist = try! PlistDictLoader(plistFileNameInBundle: Consts.serverPlistFile)
        
        if case .stringValue(let value) = try! plist.getRequired(varName: "GoogleClientId") {
            appClientId = value
        }
        
        if case .stringValue(let value) = try! plist.getRequired(varName: "GoogleServerClientId") {
            serverClientId = value
        }
    
        self.googleSignIn =  SMGoogleUserSignIn(serverClientId: serverClientId, appClientId: appClientId)
        self.googleSignIn.appLaunchSetup(silentSignIn: true)
    }
}
