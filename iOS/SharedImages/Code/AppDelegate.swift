//
//  AppDelegate.swift
//  SharedImages
//
//  Created by Christopher Prince on 3/8/17.
//  Copyright © 2017 Spastic Muffin, LLC. All rights reserved.
//

import UIKit
import CoreData
import SMCoreLib
import SyncServer

@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate {

    var window: UIWindow?
    var tabBarDelegate = TabControllerDelegate()
    var tabBarController:UITabBarController!
    
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplicationLaunchOptionsKey: Any]?) -> Bool {
    
        // Used by SMEmail in messages where email isn't allowed.
        SMUIMessages.session().appName = "Shared Images"

        let coreDataSession = CoreData(options: [
            CoreDataBundleModelName: "SharedImages",
            CoreDataSqlliteBackupFileName: "~SharedImages.sqlite",
            CoreDataSqlliteFileName: "SharedImages.sqlite",
            CoreDataLightWeightMigration: true
        ]);
        
        CoreData.registerSession(coreDataSession, forName: CoreDataExtras.sessionName)
        
        let plist = try! PlistDictLoader(plistFileNameInBundle: Consts.serverPlistFile)
        let urlString = try! plist.getString(varName: "ServerURL")
        let serverURL = URL(string: urlString)!
        let cloudFolderName = try! plist.getString(varName: "CloudFolderName")
        
        SyncServer.session.appLaunchSetup(withServerURL: serverURL, cloudFolderName:cloudFolderName)
        
        tabBarController = UIStoryboard(name: "Main", bundle: nil).instantiateViewController(withIdentifier: "TabBarController") as! UITabBarController
        tabBarController.delegate = tabBarDelegate
        window = UIWindow(frame: UIScreen.main.bounds)
        window!.rootViewController = tabBarController
                
        if SignIn.session.googleSignIn.userIsSignedIn {
            selectTabInController(tab: .images)
        }

        return true
    }
    
    enum Tab : Int {
        case signIn = 0
        case images = 1
    }
    
    func selectTabInController(tab:Tab) {
        tabBarController.selectedIndex = tab.rawValue
    }
    
    func application(_ app: UIApplication, open url: URL, options: [UIApplicationOpenURLOptionsKey : Any] = [:]) -> Bool {
        return SignIn.session.googleSignIn.application(app, openURL: url, sourceApplication: options[UIApplicationOpenURLOptionsKey.sourceApplication] as! String, annotation: options[UIApplicationOpenURLOptionsKey.annotation] as AnyObject) ||
        SharingInvitation.session.application(application: app, openURL: url, sourceApplication: options[UIApplicationOpenURLOptionsKey.sourceApplication] as! String, annotation: options[UIApplicationOpenURLOptionsKey.annotation] as AnyObject)
    }

    func applicationWillResignActive(_ application: UIApplication) {
        // Sent when the application is about to move from active to inactive state. This can occur for certain types of temporary interruptions (such as an incoming phone call or SMS message) or when the user quits the application and it begins the transition to the background state.
        // Use this method to pause ongoing tasks, disable timers, and invalidate graphics rendering callbacks. Games should use this method to pause the game.
    }

    func applicationDidEnterBackground(_ application: UIApplication) {
        // Use this method to release shared resources, save user data, invalidate timers, and store enough application state information to restore your application to its current state in case it is terminated later.
        // If your application supports background execution, this method is called instead of applicationWillTerminate: when the user quits.
    }

    func applicationWillEnterForeground(_ application: UIApplication) {
        // Called as part of the transition from the background to the active state; here you can undo many of the changes made on entering the background.
    }

    func applicationDidBecomeActive(_ application: UIApplication) {
        // Restart any tasks that were paused (or not yet started) while the application was inactive. If the application was previously in the background, optionally refresh the user interface.
    }

    func applicationWillTerminate(_ application: UIApplication) {
        CoreData.sessionNamed(CoreDataExtras.sessionName).saveContext()
    }
}

