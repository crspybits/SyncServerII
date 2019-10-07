//
//  AppleSignInCreds+ClientSecret.swift
//  Server
//
//  Created by Christopher G Prince on 10/5/19.
//

import Foundation
import SwiftJWT

// Notes about creating the client secret:
// https://auth0.com/blog/what-is-sign-in-with-apple-a-new-identity-provider/
// https://medium.com/identity-beyond-borders/adding-sign-in-with-apple-to-your-app-in-under-5mins-with-zero-code-ce36966b03f0
/* The client secret is a JWT. The parameters for this seem to be:
    1) a private key generated at:
        https://developer.apple.com/account/resources/authkeys/list
        What should you use for a Key Name?
    2) And your TEAM_ID, and KEY_ID
        The KEY_ID is from the Apple Developer Portal when you created the private key.
        The TEAM_ID is from your apple developer account.
    I'm going to use IBM's Swift-JWT package to generate this JWT at run time.
*/

struct ClientSecretPayload: Claims {
    // The issuer registered claim key, which has the value of your 10-character Team ID, obtained from your developer account.
    let iss: String
    
    // The issued at registered claim key, the value of which indicates the time at which the token was generated, in terms of the number of seconds since Epoch, in UTC.
    let iat: Date
    
    // The expiration time registered claim key, the value of which must not be greater than 15777000 (6 months in seconds) from the Current Unix Time on the server.
    let exp: Date
    
    // The audience registered claim key, the value of which identifies the recipient the JWT is intended for.
    // Since this token is meant for Apple, use https://appleid.apple.com.
    let aud: String
    
    // The subject registered claim key, the value of which identifies the principal that is the subject of the JWT. Use the same value as client_id as this token is meant for your application.
    let sub: String
}

extension AppleSignInCreds {
    func createClientSecret() -> String? {
        let privateKey = config.privateKey.replacingOccurrences(of: "\\n", with: "\n")

        guard let privateKeyData = privateKey.data(using: .utf8) else {
            return nil
        }
        
        let jwtSigner:JWTSigner
        
        // Is this going to work on Linux?
        if #available(OSX 10.13, *) {
            jwtSigner = JWTSigner.es256(privateKey: privateKeyData)
        } else {
            return nil
        }
        
        // I think by `kid`, they mean key id.
        // For the fields in the header and payload, see
        // https://developer.apple.com/documentation/signinwithapplerestapi/generate_and_validate_tokens
        let header = Header(kid: config.keyId)
                
        let expiryIntervalOneDay: TimeInterval = 60 * 60 * 24
        let exp = Date().addingTimeInterval(expiryIntervalOneDay)
        let payload = ClientSecretPayload(iss: config.teamId, iat: Date(), exp: exp, aud: "https://appleid.apple.com", sub: config.clientId)
        
        var jwt = JWT(header: header, claims: payload)
        let result = try? jwt.sign(using: jwtSigner)
        return result
    }
}
