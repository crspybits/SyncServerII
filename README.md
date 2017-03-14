Contents:  
[Introduction](#introduction)  
[Development Status](#development-status)  

# Introduction

SMSyncServer has the following general goals:  

1. Giving end-users permanent access to their mobile app data,  
1. Synchronizing mobile app data across end-user devices,  
1. Reducing data storage costs for app developers/publishers,  
1. Allowing sharing of data with other users,  
1. Cross-platform synchronization (e.g., iOS, Android), and  
1. Synchronized devices need only be [Occasionally Connected](https://msdn.microsoft.com/en-us/library/ff650163.aspx) to a network.

More detailed characteristics of the SMSyncServer:

1. The large majority of file information (i.e., all of the file content information) is stored in end-user cloud storage accounts. Only meta data for files, locks, and some user credentials information is stored in the mySQL database on the server.
1. Client apps can operate offline. The client API queues operations (e.g., uploads) until network access is available.
1. Interrupted operations are retried. For example, if network access is lost during a series of file uploads, then those uploads are retried when network access is available.

Contact: <chris@SpasticMuffin.biz> (primary developer)

# Development Status

* Previously, the server side of this project was implemented in Javascript and MongoDb. I'm now in the process of rewriting the server in Swift, and using mySQL.
* Google Drive is supported in terms of cloud storage systems.

# Standing up a Server

1. Each separate mobile app (i.e., for iOS, each app with a separate bundle id) needs its own server.

1. The server needs to run using the `GoogleServerClientId` (see below) and associated (server) client secret specific to the mobile app.

# Installation in a new iOS app

1. Setup your `Podfile`. 

    The SyncServer iOS client API is used as a Cocoapod, and because it hasn't been released yet, you will need to access the project files directly. E.g., the example apps supplied with the project use the following `Podfile`. Google SignIn is the only option currently for cloud storage, and thus the Google SignIn Cocoapod is required.

    ```
    source 'https://github.com/CocoaPods/Specs.git'
    source 'https://github.com/crspybits/Specs.git'

    use_frameworks!

    target 'SharedImages' do
        pod 'SyncServer', :path => '../Client/'
        pod 'SMCoreLib'
        pod 'Google/SignIn'
    end
    ```

1. Call `SyncServer.session.appLaunchSetup` 

    With the following import:
    
    ```
    import SyncServer 
    ```
    
    Call the following when your app first starts (e.g., in `didFinishLaunchingWithOptions`):
    
    ```
    SyncServer.session.appLaunchSetup(withServerURL: serverURL, cloudFolderName:cloudFolderName)
    ```

    `serverURL` is the URL of your SyncServer server.
    `cloudFolderName` is the folder (i.e., directory) that you want your app's files to be stored in a users cloud storage service (i.e., Google Drive at this point)
    
1. Enable your app to work with Google Drive

  1. Create Google App/Developer Credentials
  
    To enable access to user Google Drive accounts, you must create Google Developer credentials for your iOS app and SyncServer server. These credentials need to be installed in your app making use of the SyncServer Client Framework. See https://developers.google.com/identity/sign-in/ios/start and click on `GET A CONFIGURATION FILE`. You need to generate a configuration file-- this will typically be named: `GoogleService-Info.plist`, and add that file to your Xcode project.
   
    Amongst other information, this .plist file contains your Google `CLIENT_ID` for your iOS app.
   
    You also need to make sure you enable the Google Drive API for your Google project. You can do this by going to https://console.developers.google.com, looking for `ENABLE API`, and then `Drive API`.
   
    Within https://console.developers.google.com, you also need to obtain your `OAuth 2.0 client IDs` for your `Web client` (see under "Credentials). I call this the `GoogleServerClientId`. You will need both the `CLIENT_ID` (for your iOS app) and the `GoogleServerClientId` in order for users to sign in to Google Drive from your iOS app.

  1. Add URL scheme for Google Sign in to your app.

    You do this in XCode under the "Info" tab. Look for "URL Types" and paste the CLIENT_ID into the "URL Schemes" field of a new URL Type (press the "+" button).
  
  1. Use SMGoogleUserSignIn.swift to initialze Google sign in.
  
    Drag `iOS/Client/SignIn/SMGoogleUserSignIn.swift` into your Xcode project.
    
    Add the following code into your AppDelegate or someother app launch time code:
    
    ```
    let googleSignIn =  SMGoogleUserSignIn(serverClientId: GoogleServerClientId, appClientId: CLIENT_ID)
    googleSignIn.appLaunchSetup(silentSignIn: true)
    ```
    
    You will need to keep a reference to the googleSignIn object for the duration of your app's runtime. E.g., it could be a member variable of the AppDelegate.
    
    Also, add the following into your AppDelegate:
    
    ```
    func application(_ app: UIApplication, open url: URL, options: [UIApplicationOpenURLOptionsKey : Any] = [:]) -> Bool {
        return googleSignIn.application(app, openURL: url, sourceApplication: options[UIApplicationOpenURLOptionsKey.sourceApplication] as! String, annotation: options[UIApplicationOpenURLOptionsKey.annotation] as AnyObject)
    }
    ```

  1. Enable sign in to Google Drive

    In an initial view controller in your app, add a Google sign-in button:

    ```
    import UIKit
    import SMCoreLib
    
    class ViewController: SMGoogleUserSignInViewController {    
        override func viewDidLoad() {
            super.viewDidLoad()

            let googleSignInButton = SignIn.session.googleSignIn.signInButton(delegate: self)
            googleSignInButton.frameY = 100
            view.addSubview(googleSignInButton)
            googleSignInButton.centerHorizontallyInSuperview()
        }
    }
    ```
