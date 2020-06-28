//
//  ServerConfiguration.swift
//  Server
//
//  Created by Christopher Prince on 12/26/16.
//
//

import Foundation
import PerfectLib
import LoggerAPI
import ServerGoogleAccount

// Server startup configuration info, pulled from the Server.json file.

struct ServerConfiguration: Decodable, GoogleCredsConfiguration {
    /* When adding this .json into your Xcode project make sure to
    a) add it into Copy Files in Build Phases, and 
    b) select Products Directory as a destination.
    For testing, I've had to put a build script in that does:
        cp Server.json /tmp
    */
    static let serverConfigFile = "Server.json"
    
    struct mySQL: Decodable {
        let host:String
        let user:String
        let password:String
        let database:String
    }
    let db:mySQL
    
    let port:Int
    
    // For Kitura Credentials plugins
    let signInTokenTimeToLive: TimeInterval?
    
    // If you are using Google Accounts
    let GoogleServerClientId:String?
    let GoogleServerClientSecret:String?
    
    // If you are using Facebook Accounts
    let FacebookClientId:String? // This is the AppId from Facebook
    let FacebookClientSecret:String? // App Secret from Facebook
    
    // If you are using Microsoft Accounts
    let MicrosoftClientId:String?
    let MicrosoftClientSecret:String?
    
    struct AppleSignIn: Decodable {
        // From creating a Service Id for your app.
        let redirectURI: String
        
        // The reverse DNS style app identifier for your iOS app.
        let clientId: String
        
        // MARK: For generating the client secret; See notes in AppleSignInCreds+ClientSecret.swift
        
        let keyId: String
        
        let teamId: String
        
        // Once generated from the Apple developer's website, the key is converted
        // to a single line for the JSON using:
        //      awk 'NF {sub(/\r/, ""); printf "%s\\\\n",$0;}' *.p8
        // Script from https://docs.vmware.com/en/Unified-Access-Gateway/3.0/com.vmware.access-point-30-deploy-config.doc/GUID-870AF51F-AB37-4D6C-B9F5-4BFEB18F11E9.html
        let privateKey: String
    }
    let appleSignIn: AppleSignIn?

    let maxNumberDeviceUUIDPerUser:Int?
    
    struct AllowedSignInTypes: Decodable {
        let Google:Bool?
        let Facebook:Bool?
        let Dropbox:Bool?
        let Microsoft:Bool?
        let AppleSignIn: Bool?
    }
    let allowedSignInTypes:AllowedSignInTypes
    
    struct OwningUserAccountCreation: Decodable {
        let initialFileName:String?
        let initialFileContents:String?
    }
    let owningUserAccountCreation:OwningUserAccountCreation
    
    let iOSMinimumClientVersion: String?
    
    // For AWS SNS (Push Notifications)
    struct AWSSNS: Decodable {
        let accessKeyId: String?
        let secretKey: String?
        let region: String?
        let platformApplicationArn: String?
    }
    let awssns:AWSSNS?
    
    // If set to true, uses MockStorage.
    // This is a `var` only for testing-- so I can change this to true during test cases.
    var loadTestingCloudStorage: Bool?
    
#if DEBUG
    mutating func setupLoadTestingCloudStorage() {
        loadTestingCloudStorage = true
    }
#endif
}
