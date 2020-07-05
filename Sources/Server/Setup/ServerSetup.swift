//
//  ServerSetup.swift
//  Server
//
//  Created by Christopher Prince on 6/2/17.
//
//

import Foundation
import Kitura
import KituraSession
import Credentials
import CredentialsGoogle
import CredentialsFacebook
import CredentialsDropbox
import CredentialsMicrosoft
import ServerShared
import LoggerAPI
import ServerAccount
import ServerDropboxAccount
import ServerGoogleAccount
import ServerMicrosoftAccount
import ServerAppleSignInAccount
import ServerFacebookAccount

class ServerSetup {
    // Just a guess. Don't know what's suitable for length. See https://github.com/IBM-Swift/Kitura/issues/917
    private static let secretStringLength = 256
    
    private static func randomString(length: Int) -> String {

        let letters : NSString = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
        let len = UInt32(letters.length)

        var randomString = ""

        for _ in 0 ..< length {
            #if os(Linux)
                let rand = random() % Int(len)
            #else
                let rand = arc4random_uniform(len)
            #endif
            let nextChar = letters.character(at: Int(rand))
            randomString += String(UnicodeScalar(nextChar)!)
        }

        return randomString
    }

    static func credentials(_ router:Router, proxyRouter:CreateRoutes, accountManager: AccountManager) {
        let secret = self.randomString(length: secretStringLength)
        router.all(middleware: KituraSession.Session(secret: secret))
        
        // If credentials are not authorized by this middleware (e.g., valid Google creds), then an "unauthorized" HTTP code is sent back, with an empty response body.
        let credentials = Credentials()
        
        // Needed for testing.
        accountManager.reset()
        
        if Configuration.server.allowedSignInTypes.Google == true {
            let googleCredentials = CredentialsGoogleToken(tokenTimeToLive: Configuration.server.signInTokenTimeToLive)
            credentials.register(plugin: googleCredentials)
            accountManager.addAccountType(GoogleCreds.self)
        }
        
        if Configuration.server.allowedSignInTypes.Facebook == true {
            let facebookCredentials = CredentialsFacebookToken(tokenTimeToLive: Configuration.server.signInTokenTimeToLive)
            credentials.register(plugin: facebookCredentials)
            accountManager.addAccountType(FacebookCreds.self)
        }

        if Configuration.server.allowedSignInTypes.Dropbox == true {
            let dropboxCredentials = CredentialsDropboxToken(tokenTimeToLive: Configuration.server.signInTokenTimeToLive)
            credentials.register(plugin: dropboxCredentials)
            accountManager.addAccountType(DropboxCreds.self)
        }
        
        if Configuration.server.allowedSignInTypes.Microsoft == true {
            let microsoftCredentials = CredentialsMicrosoftToken(tokenTimeToLive: Configuration.server.signInTokenTimeToLive)
            credentials.register(plugin: microsoftCredentials)
            accountManager.addAccountType(MicrosoftCreds.self)
        }
        
        if Configuration.server.allowedSignInTypes.AppleSignIn == true {
//            let controller = AppleServerServerNotification()
//            func process(params:RequestProcessingParameters) {
//                //controller.
//            }
//
//            proxyRouter.addRoute(ep: AppleServerServerNotification.endpoint, processRequest: process)
        }
        
        // 8/8/17; There needs to be at least one sign-in type configured for the server to do anything. And at least one of these needs to allow owning users. If there can be no owning users, how do you create anything to share? https://github.com/crspybits/SyncServerII/issues/9
        if accountManager.numberAccountTypes == 0 {
            Log.error("There are no sign-in types configured!")
            exit(1)
        }
        
        if accountManager.numberOfOwningAccountTypes == 0 {
            Log.error("There are no owning sign-in types configured!")
            exit(1)
        }
        
        router.all { (request, response, next) in
            Log.info("REQUEST RECEIVED: \(request.urlURL.path)")
            
            for route in ServerEndpoints.session.all {
                if route.authenticationLevel == .none &&
                    route.path == request.urlURL.path {                    
                    next()
                    return
                }
            }
            
            credentials.handle(request: request, response: response, next: next)
        }
    }
}

