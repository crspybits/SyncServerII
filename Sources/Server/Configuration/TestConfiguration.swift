//
//  TestConfiguration.swift
//  Server
//
//  Created by Christopher G Prince on 9/11/19.
//

import Foundation

#if DEBUG
struct TestConfiguration: Decodable {
    // This is from crspybits@gmail.com; I created this and the two other Google refresh tokens below on 8/26/18 using method: 1) boot up testing SyncServer on AWS or locally, 2) sign in using SyncServer Example client, 3) connect into the RDS mySQL or the mySQL db locally, 4) Look at the User table for the refresh token
    let GoogleRefreshToken: String
    let GoogleSub: String
    
    // Another testing only token, for account: spasticmuffin.louisville@gmail.com. This is used for redeeming sharing invitations.
    let GoogleRefreshToken2: String
    let GoogleSub2: String
    
    // Another testing only token, for account: spastic.muffin.biz@gmail.com. For testing sharing invitations.
    let GoogleRefreshToken3: String
    let GoogleSub3: String
    
    // I think this is from crspybits@gmail.com; revoked using https://myaccount.google.com/permissions?pli=1
    let GoogleRefreshTokenRevoked: String
    let GoogleSub4: String
    
    // Facebook token for Facebook test user tnylzuhesv_1534825389@tfbnw.net; api v3.0",
    let FacebookLongLivedToken1: String
    let FacebookId1: String
  
    // Facebook token for Facebook test user xguxunxnrh_1534825386@tfbnw.net This is *not* long-lived.
    let FacebookLongLivedToken2: String
    let FacebookId2: String

    // Dropbox access tokens live forever-- until revoked-- chris@cprince.com
    let DropboxAccessToken1: String
    let DropboxId1: String
  
    // Dropbox access token -- chris@SpasticMuffin.biz
    let DropboxAccessToken2: String
    let DropboxId2: String
    
    // Dropbox access token -- chris@cprince.com-- that was revoked; see https://www.dropbox.com/account/security
    let DropboxAccessTokenRevoked: String
    let DropboxId3: String

    struct MicrosoftTokens: Decodable {
        let refreshToken: String
        
        // For bootstrapping the refresh token-- must be the "idToken" from iOS MSAL (and not the accessToken from that).
        // See https://docs.microsoft.com/en-us/azure/active-directory/develop/id-tokens
        // https://docs.microsoft.com/en-us/azure/active-directory/develop/authentication-scenarios
        // https://medium.com/@nilasini/id-token-vs-access-token-17e7dd622084
        let idToken: String
        
        // The "accessToken" from iOS MSAL
        let accessToken: String
        
        let id: String
    }
    
    // for chris@cprince.com
    let microsoft1: MicrosoftTokens
    
    // for chris@cprince.com, but an expired access token
    let microsoft1ExpiredAccessToken: MicrosoftTokens
}
#endif
