
//
//  SMGoogleUserSignIn.swift
//  SyncServer
//
//  Created by Christopher Prince on 11/26/15.
//  Copyright © 2015 Christopher Prince. All rights reserved.
//

import Google
import Foundation
import SyncServer
import SMCoreLib
import GoogleSignIn

// See https://cocoapods.org/pods/GoogleSignIn for current version of GoogleSignIn

/* 6/15/17; Just started seeing: "[!] Google has been deprecated"
    with the Google/SignIn Cocoapod when I do a `pod update`
See also: https://stackoverflow.com/questions/44398121/google-signin-cocoapod-deprecated
*/

protocol GoogleSignInDelegate : class {
func signUserOutUsing(creds:GoogleCredentials)
}

public class GoogleCredentials : GenericCredentials, CustomDebugStringConvertible {
    public var userId:String = ""
    public var username:String = ""
    
    public var uiDisplayName:String {
        return email!
    }
    
    public var email:String?
    
    fileprivate var currentlyRefreshing = false
    fileprivate var googleUser:GIDGoogleUser?

    var accessToken: String?
    
    // Used on the server to obtain a refresh code and an access token. The refresh token obtained on signin in the app can't be transferred to the server and used there.
    var serverAuthCode: String?
    
    weak var delegate:GoogleSignInDelegate?
    
    public var httpRequestHeaders:[String:String] {
        var result = [String:String]()
        result[ServerConstants.httpUsernameKey] = username
        result[ServerConstants.XTokenTypeKey] = ServerConstants.AuthTokenType.GoogleToken.rawValue
        result[ServerConstants.HTTPOAuth2AccessTokenKey] = self.accessToken
        result[ServerConstants.GoogleHTTPServerAuthCodeKey] = self.serverAuthCode
        return result
    }
    
    public var debugDescription: String {
        return "Google Access Token: \(String(describing: accessToken))"
    }
    
    enum RefreshCredentialsResult : Error {
    case noGoogleUser
    }
    
    open func refreshCredentials(completion: @escaping (Error?) ->()) {
        // See also this on refreshing of idTokens: http://stackoverflow.com/questions/33279485/how-to-refresh-authentication-idtoken-with-gidsignin-or-gidauthentication
        
        guard self.googleUser != nil
        else {
            completion(RefreshCredentialsResult.noGoogleUser)
            return
        }
        
        Synchronized.block(self) {
            if self.currentlyRefreshing {
                return
            }
            
            self.currentlyRefreshing = true
        }
        
        Log.special("refreshCredentials")
        
        self.googleUser!.authentication.refreshTokens() { auth, error in
            self.currentlyRefreshing = false
            
            if error == nil {
                Log.special("refreshCredentials: Success")
                self.accessToken = auth!.accessToken
            }
            else {
                Log.error("Error refreshing tokens: \(error!)")
                // I'm not really sure it's reasonable to sign the user out at this point, after a single attempt at refreshing credentials. It's a simple strategy, but say, what if we have no network connection. Why sign the user out then?
                self.delegate?.signUserOutUsing(creds: self)
            }
            
            completion(error)
        }
    }
}

// The class that you use to enable sign-in to Google should subclass this VC class.
class GoogleSignInViewController : UIViewController, GIDSignInUIDelegate {
}

// See https://developers.google.com/identity/sign-in/ios/sign-in
class GoogleSignIn : NSObject, GenericSignIn {


    fileprivate let serverClientId:String!
    fileprivate let appClientId:String!
    
    fileprivate let signInOutButton = GoogleSignInOutButton()
    
    weak public var delegate:GenericSignInDelegate?    
    weak public var signOutDelegate:GenericSignOutDelegate!
   
    public init(serverClientId:String, appClientId:String) {
        self.serverClientId = serverClientId
        self.appClientId = appClientId
        super.init()
        self.signInOutButton.signOutButton.addTarget(self, action: #selector(signUserOut), for: .touchUpInside)
    }
    
    open func appLaunchSetup(silentSignIn: Bool) {
    
        var configureError: NSError?
        GGLContext.sharedInstance().configureWithError(&configureError)
        assert(configureError == nil, "Error configuring Google services: \(String(describing: configureError))")
        
        GIDSignIn.sharedInstance().delegate = self
        
        // Seem to need the following for accessing the serverAuthCode. Plus, you seem to need a "fresh" sign-in (not a silent sign-in). PLUS: serverAuthCode is *only* available when you don't do the silent sign in.
        // https://developers.google.com/identity/sign-in/ios/offline-access?hl=en
        GIDSignIn.sharedInstance().serverClientID = self.serverClientId
        GIDSignIn.sharedInstance().clientID = self.appClientId

        // 8/20/16; I had a difficult to resolve issue relating to scopes. I had re-created a file used by SharedNotes, outside of SharedNotes, and that application was no longer able to access the file. See https://developers.google.com/drive/v2/web/scopes The fix to this issue was in two parts: 1) to change the scope to access all of the users files, and to 2) force updating of the access_token/refresh_token on the server. (I did this later part by hand-- it would be good to be able to force this automatically).
        
        // "Per-file access to files created or opened by the app"
        // GIDSignIn.sharedInstance().scopes.append("https://www.googleapis.com/auth/drive.file")
        
        // "Full, permissive scope to access all of a user's files."
        GIDSignIn.sharedInstance().scopes.append("https://www.googleapis.com/auth/drive")
        
        // 12/20/15; Trying to resolve my user sign in issue
        // It looks like, at least for Google Drive, calling this method is sufficient for dealing with rcStaleUserSecurityInfo. I.e., having the IdToken for Google become stale. (Note that while it deals with the IdToken becoming stale, dealing with an expired access token on the server is a different matter-- and the server seems to need to refresh the access token from the refresh token to deal with this independently).
        // See also this on refreshing of idTokens: http://stackoverflow.com/questions/33279485/how-to-refresh-authentication-idtoken-with-gidsignin-or-gidauthentication
        if silentSignIn {
            GIDSignIn.sharedInstance().signInSilently()
            //let creds = signedInUser(forUser: user)
        }
        else {
            // I'm doing this to force a user-signout, so that I get the serverAuthCode. Seems I only get this with the user explicitly signed out before hand.
            GIDSignIn.sharedInstance().signOut()
        }
    }

    open func application(_ application: UIApplication!, openURL url: URL!, sourceApplication: String!, annotation: AnyObject!) -> Bool {
        return GIDSignIn.sharedInstance().handle(url, sourceApplication: sourceApplication,
            annotation: annotation)
    }
    
    var userIsSignedIn: Bool {
        Log.msg("GIDSignIn.sharedInstance().currentUser: \(GIDSignIn.sharedInstance().currentUser)")
        return GIDSignIn.sharedInstance().hasAuthInKeychain()
    }
        
    public var credentials:GenericCredentials? {
        return signedInUser(forUser: GIDSignIn.sharedInstance().currentUser)
    }
    
    func signedInUser(forUser user:GIDGoogleUser) -> GoogleCredentials {
        let name = user.profile.name
        let email = user.profile.email

        let creds = GoogleCredentials()
        creds.userId = user.userID
        creds.email = email
        creds.username = name!
        creds.accessToken = user.authentication.accessToken
        Log.msg("user.serverAuthCode: \(user.serverAuthCode)")
        creds.serverAuthCode = user.serverAuthCode
        creds.googleUser = user
        
        creds.delegate = self
        
        return creds
    }
    
    // The parameter must be given as "delegate" with a value of a `GoogleSignInViewController`. Returns an object of type `GoogleSignInOutButton`.
    public func getSignInButton(params:[String:Any]) -> UIView? {
        guard let vcDelegate = params["delegate"] as? GoogleSignInViewController else {
            Log.error("You must give a GoogleUserSignInViewController delegate parameter")
            return nil
        }
    
        // 7/7/16; Prior to Google Sign In 4.0, this delegate was on the signInOutButton button. But now, its on the GIDSignIn. E.g., see https://developers.google.com/identity/sign-in/ios/api/protocol_g_i_d_sign_in_delegate-p
        GIDSignIn.sharedInstance().delegate = self
        
        GIDSignIn.sharedInstance().uiDelegate = vcDelegate
        
        return self.signInOutButton
    }
}

extension GoogleSignIn : GoogleSignInDelegate {
    func signUserOutUsing(creds:GoogleCredentials) {
        self.signUserOut()
    }
}

// // MARK: UserSignIn methods.
extension GoogleSignIn {
    @objc public func signUserOut() {
        GIDSignIn.sharedInstance().signOut()
        signInOutButton.buttonShowing = .signIn
        signOutDelegate.userWasSignedOut(signIn: self)
        delegate?.userActionOccurred(action: .userSignedOut, signIn: self)
    }
}

extension GoogleSignIn : GIDSignInDelegate {
    public func sign(_ signIn: GIDSignIn!, didSignInFor user: GIDGoogleUser!, withError error: Error!)
    {
        if (error == nil) {
            self.signInOutButton.buttonShowing = .signOut
            let creds = signedInUser(forUser: user)

            guard let userAction = self.delegate?.shouldDoUserAction(signIn: self) else {
                // This occurs if we don't have a delegate (e.g., on a silent sign in). But, we need to set up creds-- because this is what gives us credentials for connecting to the SyncServer.
                SyncServerUser.session.creds = creds
                return
            }

            // TODO: *0* Put up a spinner-- if we have an error, it can take a while.
            
            switch userAction {
            case .signInExistingUser:
                SyncServerUser.session.checkForExistingUser(creds: creds) {
                    (checkForUserResult, error) in
                    if error == nil {
                        switch checkForUserResult! {
                        case .noUser:
                            self.delegate?.userActionOccurred(action:
                                .userNotFoundOnSignInAttempt, signIn: self)
                        case .owningUser:
                            self.delegate?.userActionOccurred(action: .existingUserSignedIn(nil), signIn: self)
                        case .sharingUser(sharingPermission: let permission):
                            self.delegate?.userActionOccurred(action: .existingUserSignedIn(permission), signIn: self)
                        }
                    }
                    else {
                        // TODO: *0* Give the user an error indication.
                        Log.error("Error checking for existing user: \(String(describing: error))")
                        self.signUserOut()
                    }
                }
                
            case .createOwningUser:
                SyncServerUser.session.addUser(creds: creds) { error in
                    if error == nil {
                        self.delegate?.userActionOccurred(action: .owningUserCreated, signIn: self)
                    }
                    else {
                        // TODO: *0* Give the user an error indication.
                        self.signUserOut()
                    }
                }
                
            case .createSharingUser(invitationCode: let invitationCode):
                SyncServerUser.session.redeemSharingInvitation(creds: creds, invitationCode: invitationCode) { error in
                    if error == nil {
                        self.delegate?.userActionOccurred(action: .sharingUserCreated, signIn: self)
                    }
                    else {
                        // TODO: *0* Give the user an error indication.
                        self.signUserOut()
                    }
                }
            
            case .none:
                break
            }
        }
        else {
            Log.error("Error signing into Google: \(error)")
            // So we don't have the UI saying we're signed in, but we're actually not.
            signUserOut()
        }
    }
    
    public func sign(_ signIn: GIDSignIn!, didDisconnectWith user: GIDGoogleUser!, withError error: Error!)
    {
    }
}

// Self-sized; cannot be resized.
public class GoogleSignInOutButton : UIView {
    let signInButton = GIDSignInButton()
    
    let signOutButtonContainer = UIView()
    let signOutContentView = UIView()
    let signOutButton = UIButton(type: .system)
    let signOutLabel = UILabel()
    
    init() {
        super.init(frame: CGRect.zero)
        self.addSubview(signInButton)
        self.addSubview(self.signOutButtonContainer)
        
        self.signOutButtonContainer.addSubview(self.signOutContentView)
        self.signOutButtonContainer.addSubview(signOutButton)
       
        let googleIconView = UIImageView(image: SMIcons.GoogleIcon)
        googleIconView.contentMode = .scaleAspectFit
        self.signOutContentView.addSubview(googleIconView)
        
        self.signOutLabel.text = "Sign out"
        self.signOutLabel.font = UIFont.boldSystemFont(ofSize: 15.0)
        self.signOutLabel.sizeToFit()
        self.signOutContentView.addSubview(self.signOutLabel)
        
        let frame = signInButton.frame
        self.bounds = frame
        self.signOutButton.frame = frame
        self.signOutButtonContainer.frame = frame
        
        let margin:CGFloat = 20
        self.signOutContentView.frame = frame
        self.signOutContentView.frameHeight -= margin
        self.signOutContentView.frameWidth -= margin
        self.signOutContentView.centerInSuperview()
        
        let iconSize = frame.size.height * 0.4
        googleIconView.frameSize = CGSize(width: iconSize, height: iconSize)
        
        googleIconView.centerVerticallyInSuperview()
        
        self.signOutLabel.frameMaxX = self.signOutContentView.boundsMaxX
        self.signOutLabel.centerVerticallyInSuperview()

        let layer = self.signOutButton.layer
        layer.borderColor = UIColor.lightGray.cgColor
        layer.borderWidth = 0.5
        
        self.buttonShowing = .signIn
    }
    
    required public init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override public func layoutSubviews() {
        super.layoutSubviews()
    }
    
    enum State {
        case signIn
        case signOut
    }
    
    fileprivate var _state:State!
    var buttonShowing:State {
        get {
            return self._state
        }
        
        set {
            Log.msg("Change sign-in state: \(newValue)")
            self._state = newValue
            switch self._state! {
            case .signIn:
                self.signInButton.isHidden = false
                self.signOutButtonContainer.isHidden = true
            
            case .signOut:
                self.signInButton.isHidden = true
                self.signOutButtonContainer.isHidden = false
            }
            
            self.setNeedsDisplay()
        }
    }
    
    func tap() {
        switch buttonShowing {
        case .signIn:
            self.signInButton.sendActions(for: .touchUpInside)
            
        case .signOut:
            self.signOutButton.sendActions(for: .touchUpInside)
        }
    }
}
