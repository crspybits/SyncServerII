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
import ServerShared
import LoggerAPI

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

    static func credentials(_ router:Router, accountManager: AccountManager) -> [ServerRoute] {
        let secret = self.randomString(length: secretStringLength)
        router.all(middleware: KituraSession.Session(secret: secret))
        
        // If credentials are not authorized by this middleware (e.g., valid Google creds), then an "unauthorized" HTTP code is sent back, with an empty response body.
        let credentials = Credentials()
        
        // Needed for testing.
        accountManager.reset()
        
        let accountRoutes = accountManager.setupAccounts(credentials: credentials)
        let accountEndpoints:[ServerEndpoint] = accountRoutes.map {$0.0}
        
        router.all { (request, response, next) in
            Log.info("REQUEST RECEIVED: \(request.urlURL.path)")
            
            // If the endpoint doesn't require authentication, handle it specially.
            for route in ServerEndpoints.session.all + accountEndpoints {
                if route.authenticationLevel == .none &&
                    route.path == request.urlURL.path {
                    Log.info("Handling without credentials: \(request.urlURL.path)")
                    next()
                    return
                }
            }
            
            Log.info("Handling with credentials: \(request.urlURL.path)")

            credentials.handle(request: request, response: response, next: next)
        }
        
        return accountRoutes
    }
}

