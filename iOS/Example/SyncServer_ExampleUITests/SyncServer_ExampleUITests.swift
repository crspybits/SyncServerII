//
//  SyncServer_ExampleUITests.swift
//  SyncServer_ExampleUITests
//
//  Created by Christopher Prince on 6/17/17.
//  Copyright © 2017 CocoaPods. All rights reserved.
//

import XCTest

class SyncServer_ExampleUITests: XCTestCase {
        
    override func setUp() {
        super.setUp()
        
        // Put setup code here. This method is called before the invocation of each test method in the class.
        
        // In UI tests it is usually best to stop immediately when a failure occurs.
        continueAfterFailure = false
        // UI tests must launch the application that they test. Doing this in setup will make sure it happens for each test method.
        XCUIApplication().launch()

        // In UI tests it’s important to set the initial state - such as interface orientation - required for your tests before they run. The setUp method is a good place to do this.
    }
    
    override func tearDown() {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
        super.tearDown()
    }
    
    // Assumes that user already exists on the server.
    // Causes use of some server API such as FileIndex, all of course after having properly setup creds with the ServerAPI.session. The problem I've been having is that I can't use GoogleSignInCreds from my normal unit tests.
    /*
    func testCredentialsRefresh() {
        // First press the button on the UI
        
        let app = XCUIApplication()
        app.buttons["GIDSignInButton"].tap()
        
        // Need a button press on the Google Sign In screen.
        // Hmmm. Don't know how to do that yet. The Xcode record function doesn't do it. See also: https://stackoverflow.com/questions/36116009/google-sign-in-on-ios-can-not-be-recorded-using-xcode-ui-testing-inspector-perh
        // And see https://stackoverflow.com/questions/36770289/how-to-write-ui-tests-covering-login-with-facebook-in-xcode
        
        app.buttons["Test Credentials Refresh"].tap()
        
    }
    */
}
