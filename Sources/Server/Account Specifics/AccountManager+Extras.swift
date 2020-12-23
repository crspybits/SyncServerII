//
//  AccountManager+Extras.swift
//  Server
//
//  Created by Christopher G Prince on 7/12/20.
//

import Foundation
import Credentials
import ServerAccount
import ServerDropboxAccount
import ServerGoogleAccount
import ServerMicrosoftAccount
import ServerAppleSignInAccount
import ServerFacebookAccount
import CredentialsGoogle
import CredentialsFacebook
import CredentialsDropbox
import CredentialsMicrosoft
import CredentialsAppleSignIn
import LoggerAPI

extension AccountManager {
    func setupAccounts(credentials: Credentials) -> [ServerRoute] {
        var resultRoutes = [ServerRoute]()
        
        if Configuration.server.allowedSignInTypes.Google == true {
            let googleCredentials = CredentialsGoogleToken(tokenTimeToLive: Configuration.server.signInTokenTimeToLive)
            credentials.register(plugin: googleCredentials)
            addAccountType(GoogleCreds.self)
        }
        
        if Configuration.server.allowedSignInTypes.Facebook == true {
            let facebookCredentials = CredentialsFacebookToken(tokenTimeToLive: Configuration.server.signInTokenTimeToLive)
            credentials.register(plugin: facebookCredentials)
            addAccountType(FacebookCreds.self)
        }

        if Configuration.server.allowedSignInTypes.Dropbox == true {
            let dropboxCredentials = CredentialsDropboxToken(tokenTimeToLive: Configuration.server.signInTokenTimeToLive)
            credentials.register(plugin: dropboxCredentials)
            addAccountType(DropboxCreds.self)
        }
        
        if Configuration.server.allowedSignInTypes.Microsoft == true {
            let microsoftCredentials = CredentialsMicrosoftToken(tokenTimeToLive: Configuration.server.signInTokenTimeToLive)
            credentials.register(plugin: microsoftCredentials)
            addAccountType(MicrosoftCreds.self)
        }
        
        if Configuration.server.allowedSignInTypes.AppleSignIn == true {
            let controller = AppleServerServerNotification()

            func process(params:RequestProcessingParameters) {
                Log.debug("AppleServerServerNotification: Got request.")
                // TODO: So far the update isn't doing anything. Seems like what we'll need to do here is to disable or remove Apple Sign In accounts where the server to server notification tells us that the account is no longer valid.
                controller.update()
                
                if let request = params.request as? NotificationRequest {
                    let requestDataString = String(data: request.data, encoding: .utf8)
                    Log.debug("AppleServerServerNotification: requestDataString: \(String(describing: requestDataString))")
                }
                else {
                    Log.error("AppleServerServerNotification: Request wasn't a NotificationRequest")
                }
            }

            let appleServerToServerRoute:ServerRoute = (AppleServerServerNotification.endpoint, process)

            if let clientId = Configuration.server.appleSignIn?.clientId {
                let appleCredentials = CredentialsAppleSignInToken(clientId: clientId, tokenTimeToLive: Configuration.server.signInTokenTimeToLive)
                credentials.register(plugin: appleCredentials)
                addAccountType(AppleSignInCreds.self)
                resultRoutes += [appleServerToServerRoute]
            }
            else {
                Log.warning("No Configuration.server.appleSignIn.clientId; cannot register CredentialsAppleSignInToken")
            }
        }
        
        // 8/8/17; There needs to be at least one sign-in type configured for the server to do anything. And at least one of these needs to allow owning users. If there can be no owning users, how do you create anything to share? https://github.com/crspybits/SyncServerII/issues/9
        if numberAccountTypes == 0 {
            Startup.halt("There are no sign-in types configured!")
            return []
        }
        
        if numberOfOwningAccountTypes == 0 {
            Startup.halt("There are no owning sign-in types configured!")
            return []
        }
        
        return []
    }
}
