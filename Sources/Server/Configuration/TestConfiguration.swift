//
//  TestConfiguration.swift
//  Server
//
//  Created by Christopher G Prince on 9/11/19.
//

import Foundation

// I've put this in the Server files because I've added it into the Configuration as well, for easier access.

#if DEBUG
struct TestConfiguration: Decodable {
    /* This is from crspybits@gmail.com; I created this and the two other Google refresh tokens below on 8/26/18 using method:
        1) boot up testing SyncServer on AWS or locally,
        2) sign in using SyncServer Example client,
        3) connect into the RDS mySQL or the mySQL db locally,
            * Look at the User table for the refresh token
        4) OR: Look in the server log for "refreshToken:".
    */
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
    // To refresh these, go to https://developers.facebook.com/apps/ and SyncServerTests,
    // then Roles > Test Users
    // Use Edit > "Get an access token for this test user"
    // Do this for both of the Facebook tokens, and then run
    //      ./Tools/getLongLivedFacebookToken.sh ServerTests.json
    // under Mac OS
    let FacebookLongLivedToken1: String
    let FacebookId1: String
  
    // Facebook token for Facebook test user xguxunxnrh_1534825386@tfbnw.net This is *not* long-lived.
    let FacebookLongLivedToken2: String
    let FacebookId2: String

    // Dropbox access tokens live forever-- until revoked-- chris@cprince.com
    let DropboxRefreshToken1: String
    let DropboxId1: String
  
    // Dropbox access token -- chris@SpasticMuffin.biz
    let DropboxAccessToken2: String
    let DropboxId2: String
    
    // Dropbox access token -- chris@cprince.com-- that was revoked; see https://www.dropbox.com/account/security
    let DropboxAccessTokenRevoked: String
    let DropboxId3: String

    /* Regenerating refresh token:
        1) For a specific microsoft account, sign in using the microsoft ms-identity-mobile-apple-swift-objc-master/MSALiOS app.
        2) Grab the id token from the console.
        3) Copy that token into /Users/chris/Desktop/Apps/SyncServerII/Private/ServerMicrosoftAccount/token.plist
        4) Run the ServerMicrosoftAccount Swift Package testGenerateTokens test method.
        5) Copy the refresh token from the console to the server testing configuration, along with the id token.
     */
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
    
    // for crspybits@gmail.com
    let microsoft2: MicrosoftTokens
    
    // for chris@cprince.com, but an expired access token
    let microsoft1ExpiredAccessToken: MicrosoftTokens
    
    /* This is somewhat tricky to generate.
        1) Make a new account,
        1) Generate an accessToken (in iOS MSAL's terminology).
        2) Revoke the rights of Neebla from this account
        The access token, at least until it is expired, should be purely a revoked access token.
    */
    let microsoft2RevokedAccessToken: MicrosoftTokens
    
    /*
    I'm not sure why but the identity token (`idToken`) that's getting written into the SyncServer db is different than that passed up from Neebla. Both seem to work in my tests.
     */
    struct AppleSignInTokens: Decodable {
        let authorizationCode: String
        let refreshToken: String
        let idToken: String
        let id: String
    }
    
    let apple1: AppleSignInTokens
}
#endif
