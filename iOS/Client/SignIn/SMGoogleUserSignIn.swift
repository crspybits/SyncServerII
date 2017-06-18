
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

/* 6/15/17; Just started seeing: "[!] Google has been deprecated"
    with the Google/SignIn Cocoapod when I do a `pod update`
See also: https://stackoverflow.com/questions/44398121/google-signin-cocoapod-deprecated
*/

/* 6/25/16; Just started seeing this issue: https://forums.developer.apple.com/message/148335#148335
Failed to get remote view controller with error: Error Domain=NSCocoaErrorDomain Code=4097 "connection to service named com.apple.uikit.viewservice.com.apple.SafariViewService" UserInfo={NSDebugDescription=connection to service named com.apple.uikit.viewservice.com.apple.SafariViewService}
It's only happening in the simulator. The console log also shows:
A new version of the Google Sign-In iOS SDK is available: https://developers.google.com/identity/sign-in/ios/release
so, it's possible this issue has been resolved.
*/
/* TODO: Handle this: Got it when I pressed the Sign In button to connect to Google.
2015-11-26 21:09:38.198 NetDb[609/0x16e12f000] [lvl=3] __65-[GGLClearcutLogger sendNextPendingRequestWithCompletionHandler:]_block_invoke_3() Error posting to Clearcut: Error Domain=NSURLErrorDomain Code=-1005 "The network connection was lost." UserInfo={NSUnderlyingError=0x15558de70 {Error Domain=kCFErrorDomainCFNetwork Code=-1005 "(null)" UserInfo={_kCFStreamErrorCodeKey=57, _kCFStreamErrorDomainKey=1}}, NSErrorFailingURLStringKey=https://play.googleapis.com/log, NSErrorFailingURLKey=https://play.googleapis.com/log, _kCFStreamErrorDomainKey=1, _kCFStreamErrorCodeKey=57, NSLocalizedDescription=The network connection was lost.}
*/

// 7/7/16. Just solved a problem linking with the new Google SignIn. The resolution amounted to . See https://stackoverflow.com/questions/37715067/pods-headers-public-google-google-signin-h19-gglcore-gglcore-h-file-not-fo

protocol GoogleSignInCredsDelegate : class {
func signUserOutUsing(creds:GoogleSignInCreds)
}

class GoogleSignInCreds : SignInCreds, CustomDebugStringConvertible {
    fileprivate var currentlyRefreshing = false
    fileprivate var googleUser:GIDGoogleUser?

    var idToken: String?
    var accessToken: String?
    
    // Used on the server to obtain a refresh code and an access token. The refresh token obtained on signin in the app can't be transferred to the server and used there.
    var serverAuthCode: String?
    
    weak var delegate:GoogleSignInCredsDelegate?
    
    override public func authDict() -> [String:String] {
        var result = super.authDict()
        result[ServerConstants.XTokenTypeKey] = ServerConstants.AuthTokenType.GoogleToken.rawValue
        result[ServerConstants.GoogleHTTPAccessTokenKey] = self.accessToken
        result[ServerConstants.GoogleHTTPServerAuthCodeKey] = self.serverAuthCode
        return result
    }
    
    public var debugDescription: String {
        return "Google Access Token: \(String(describing: accessToken))"
    }
    
    enum RefreshCredentialsResult : Error {
    case noGoogleUser
    }
    
    override open func refreshCredentials(completion: @escaping (Error?) ->()) {
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
                self.idToken = auth!.idToken
                self.accessToken = auth!.accessToken
            }
            else {
                Log.error("Error refreshing tokens: \(String(describing: error))")
                // I'm not really sure it's reasonable to sign the user out at this point, after a single attempt at refreshing credentials. It's a simple strategy, but say, what if we have no network connection. Why sign the user out then?
                self.delegate?.signUserOutUsing(creds: self)
            }
            
            completion(error)
        }
    }
}

// The class that you used to enable sign-in to Google should subclass this VC class.
open class SMGoogleUserSignInViewController : UIViewController, GIDSignInUIDelegate {
}

public enum UserActionNeeded {
case createSharingUser(invitationCode:String)
case createOwningUser
case signInExistingUser
case none // e.g., error
}

public enum UserActionOccurred {
case userSignedOut
case userNotFoundOnSignInAttempt
case existingUserSignedIn(SharingPermission?)
case sharingUserCreated
case owningUserCreated
}

protocol SMGoogleUserSignInDelegate : class {
func shouldDoUserAction(googleUserSignIn:SMGoogleUserSignIn) -> UserActionNeeded
func userActionOccurred(action:UserActionOccurred, googleUserSignIn:SMGoogleUserSignIn)
}

// See https://developers.google.com/identity/sign-in/ios/sign-in
open class SMGoogleUserSignIn : NSObject {
    // Specific to Google Credentials. I'm not sure it's needed really (i.e., could it be obtained each time the app launches on sign in-- since to be signed in really assumes we're connected to the network?), but I'll store this in the Keychain since it's credential info.
    // Hmmmm. I may be making incorrect assumptions about the longevity of these IdTokens. See https://github.com/google/google-auth-library-nodejs/issues/46 Does silently signing the user in generate a new IdToken?
    fileprivate static let IdToken = SMPersistItemString(name: "SMGoogleUserSignIn.IdToken", initialStringValue: "", persistType: .keyChain)

    fileprivate static let _googleUserName = SMPersistItemString(name: "SMGoogleUserSignIn.googleUserName", initialStringValue: "", persistType: .userDefaults)
    
    fileprivate var googleUserName:String? {
        get {
            return SMGoogleUserSignIn._googleUserName.stringValue == "" ? nil : SMGoogleUserSignIn._googleUserName.stringValue
        }
        set {
            SMGoogleUserSignIn._googleUserName.stringValue =
                newValue == nil ? "" : newValue!
        }
    }
    
    fileprivate let serverClientId:String!
    fileprivate let appClientId:String!
    
    fileprivate var idToken:String! {
        set {
            SMGoogleUserSignIn.IdToken.stringValue = newValue
        }
        
        get {
            return SMGoogleUserSignIn.IdToken.stringValue
        }
    }
    
    fileprivate let signInOutButton = GoogleSignInOutButton()
    
    weak var delegate:SMGoogleUserSignInDelegate?
   
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
    
    /* Sometimes I get this when I try to silently sign in:
    
    Error signing in: Error Domain=com.google.GIDSignIn Code=-4 "(null)"
    ***** Error signing in: Optional(Error Domain=com.google.GIDSignIn Code=-4 "(null)")
    2015-12-11 02:55:21 +0000: [fg0,0,255;type: UserDefaults; name: DefsUserIsSignedIn; initialValue: 0; initialValueType: ImplicitlyUnwrappedOptional<AnyObject>[; [init(name:initialValue:persistType:) in SMPersistVars.swift, line 43]
    Error signing in: Error Domain=com.google.GIDSignIn Code=-4 "(null)"
    ***** Error signing in: Optional(Error Domain=com.google.GIDSignIn Code=-4 "(null)")         
    */
    // See http://stackoverflow.com/questions/31461139/signinsilently-generates-an-error-code-4
    // And see https://github.com/googlesamples/google-services/issues/27
    /* How is this Code=-4 error related (if at all) to the "verifyIdToken error: TypeError: Not a buffer" issue I'm getting on the server? Could it be that when I rebuild the iOS app, this occurs? To test this, I could wait for a considerable period of time (e.g., 1 day), and try to do an operation like Get File Index, all without rebuilding the iOS app. If I still get the "Not a buffer" error, when previously, the IdToken was working fine, then this is not an issue about rebuilding the app.
    On the client side, it seems that once I've gotten the "Not a buffer" error from the server, and I try to do the silent sign-in again on the client, I get this Code=-4 error.
    */
    /* I just got "User security token is stale" on the server, and a Code=-4 on the client when I tried to do the silently sign in. This happened to be after I did a deletion and rebuild of the app.
    */
    /* 12/13/15; I just got the "error: Not a buffer" on the server. Then I tried a silent sign in from the app, it worked. Note that while I had just rebuilt the app, I hadn't deleted it immediately before rebuilding.
    */
    /* 12/15/15; I just got the "error: Not a buffer" on the server. Then I tried a silent sign in from the app, and it failed with the Code=-4 error. I had just rebuilt the app, but I hadn't deleted the app immediately before.
    */
    // See https://cocoapods.org/pods/GoogleSignIn for current version of GoogleSignIn
    

    var userIsSignedIn: Bool {
        Log.msg("GIDSignIn.sharedInstance().currentUser: \(GIDSignIn.sharedInstance().currentUser)")
        return GIDSignIn.sharedInstance().hasAuthInKeychain()
    }
    
    var signedInUser: GoogleSignInCreds {
        return signedInUser(forUser: GIDSignIn.sharedInstance().currentUser)
    }
    
    func signedInUser(forUser user:GIDGoogleUser) -> GoogleSignInCreds {
        let name = user.profile.name
        let email = user.profile.email
        
        if email != nil {
            self.googleUserName = email
        }
        else {
            self.googleUserName = name
        }

        let creds = GoogleSignInCreds()
        creds.userId = user.userID
        creds.email = email
        creds.username = name
        creds.idToken = user.authentication.idToken
        creds.accessToken = user.authentication.accessToken
        Log.msg("user.serverAuthCode: \(user.serverAuthCode)")
        creds.serverAuthCode = user.serverAuthCode
        creds.googleUser = user
        
        creds.delegate = self
        
        return creds
    }
    
    open func signInButton(delegate: SMGoogleUserSignInViewController) -> GoogleSignInOutButton {
    
        // 7/7/16; Prior to Google Sign In 4.0, this delegate was on the signInOutButton button. But now, its on the GIDSignIn. E.g., see https://developers.google.com/identity/sign-in/ios/api/protocol_g_i_d_sign_in_delegate-p
        GIDSignIn.sharedInstance().delegate = self
        
        GIDSignIn.sharedInstance().uiDelegate = delegate

        // self.signInOutButton.buttonShowing = self.delegate.smUserSignIn(activelySignedIn: self) ? .SignOut : .SignIn
        
        return self.signInOutButton
    }
}

extension SMGoogleUserSignIn : GoogleSignInCredsDelegate {
    func signUserOutUsing(creds:GoogleSignInCreds) {
        self.signUserOut()
    }
}

// // MARK: UserSignIn methods.
extension SMGoogleUserSignIn {
    @objc public func signUserOut() {
        GIDSignIn.sharedInstance().signOut()
        self.signInOutButton.buttonShowing = .signIn
        self.delegate?.userActionOccurred(action: .userSignedOut, googleUserSignIn: self)
    }
}

extension SMGoogleUserSignIn : GIDSignInDelegate {
    public func sign(_ signIn: GIDSignIn!, didSignInFor user: GIDGoogleUser!, withError error: Error!)
    {
        if (error == nil) {
            self.signInOutButton.buttonShowing = .signOut
            let creds = signedInUser(forUser: user)

            guard let userAction = self.delegate?.shouldDoUserAction(googleUserSignIn: self) else {
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
                                .userNotFoundOnSignInAttempt, googleUserSignIn: self)
                        case .owningUser:
                            self.delegate?.userActionOccurred(action: .existingUserSignedIn(nil), googleUserSignIn: self)
                        case .sharingUser(sharingPermission: let permission):
                            self.delegate?.userActionOccurred(action: .existingUserSignedIn(permission), googleUserSignIn: self)
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
                        self.delegate?.userActionOccurred(action: .owningUserCreated, googleUserSignIn: self)
                    }
                    else {
                        // TODO: *0* Give the user an error indication.
                        self.signUserOut()
                    }
                }
                
            case .createSharingUser(invitationCode: let invitationCode):
                SyncServerUser.session.redeemSharingInvitation(creds: creds, invitationCode: invitationCode) { error in
                    if error == nil {
                        self.delegate?.userActionOccurred(action: .sharingUserCreated, googleUserSignIn: self)
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
