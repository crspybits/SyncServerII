//
//  ViewController.swift
//  SyncServer
//
//  Created by Christopher Prince on 11/29/16.
//  Copyright © 2016 Spastic Muffin, LLC. All rights reserved.
//

import UIKit
import SMCoreLib
@testable import SyncServer
import SevenSwitch

class ViewController: GoogleSignInViewController {
    var googleSignInButton:UIView!
    fileprivate var signinTypeSwitch:SevenSwitch!
    var syncServerEventOccurred: ((_ : SyncEvent)->())?
    var syncServerSingleFileUploadCompleted: (()->())?
    @IBOutlet weak var testingOutcome: UILabel!
    
    // So far, this needs to be run manually, after you've signed in. Also-- you may need to delete the current FileIndex contents in the database, and delete the app.
    @IBAction func testCredentialsRefreshAction(_ sender: Any) {
        self.testingOutcome.text = nil
        self.testingOutcome.setNeedsDisplay()

        SyncServer.session.eventsDesired = [.refreshingCredentials, .fileUploadsCompleted, .syncDone]
        SyncServer.session.delegate = self

        // These are a bit of a hack to do this testing.
        let user = SetupSignIn.session.googleSignIn.credentials as! GoogleCredentials
        user.accessToken = "foobar"
        SyncServerUser.session.creds = user
        
        var numberUploads = 0
        var refresh = 0
        var uploadsCompleted = 0
        
        syncServerEventOccurred = { event in
            switch event {
            case .syncDone:
                if refresh == 1 && uploadsCompleted == 1 {
                    self.testingOutcome.text = "success!"
                }
                else {
                    self.testingOutcome.text = "failed"
                }
                
            case .refreshingCredentials:
                refresh += 1
                
            case .fileUploadsCompleted(numberOfFiles: let numberOfFiles):
                assert(numberOfFiles == numberUploads, "numberOfFiles: \(numberOfFiles); numberUploads: \(numberUploads)")
                uploadsCompleted += 1
                
            default:
                assert(false)
            }
        }
        
        syncServerSingleFileUploadCompleted = {
            numberUploads += 1
        }
        
        let url = SMRelativeLocalURL(withRelativePath: "UploadMe2.txt", toBaseURLType: .mainBundle)!
        let uuid = UUID().uuidString
        let attr = SyncAttributes(fileUUID: uuid, mimeType: "text/plain", creationDate: Date(), updateDate: Date())
        try! SyncServer.session.uploadImmutable(localFile: url, withAttributes: attr)
        SyncServer.session.sync()
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        googleSignInButton = SetupSignIn.session.googleSignIn.getSignInButton(params: ["delegate": self])
        googleSignInButton.frameY = 100
        view.addSubview(googleSignInButton)
        googleSignInButton.centerHorizontallyInSuperview()
        
        SetupSignIn.session.googleSignIn.delegate = self
        
        signinTypeSwitch = SevenSwitch()
        signinTypeSwitch.offLabel.text = "Existing user"
        signinTypeSwitch.offLabel.textColor = UIColor.black
        signinTypeSwitch.onLabel.text = "New user"
        signinTypeSwitch.onLabel.textColor = UIColor.black
        signinTypeSwitch.frameY = googleSignInButton.frameMaxY + 30
        signinTypeSwitch.frameWidth = 120
        signinTypeSwitch.inactiveColor =  UIColor(red: 0.5, green: 0.5, blue: 0.5, alpha: 1)
        signinTypeSwitch.onTintColor = UIColor(red: 16.0/255.0, green: 125.0/255.0, blue: 247.0/255.0, alpha: 1)
        view.addSubview(signinTypeSwitch)
        signinTypeSwitch.centerHorizontallyInSuperview()
        
        setSignInTypeState()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
    }
    
    func setSignInTypeState() {
        signinTypeSwitch?.isHidden = SetupSignIn.session.googleSignIn.userIsSignedIn
    }
}

extension ViewController : GenericSignInDelegate {
    func shouldDoUserAction(signIn: GenericSignIn) -> UserActionNeeded {
        var result:UserActionNeeded
        
        if signinTypeSwitch.isOn() {
            result = .createOwningUser
        }
        else {
            result = .signInExistingUser
        }
        
        return result
    }
    
    func userActionOccurred(action:UserActionOccurred, signIn: GenericSignIn) {
        switch action {
        case .userSignedOut:
            break
            
        case .userNotFoundOnSignInAttempt:
            Log.error("User not found on sign in attempt")
            
        case .existingUserSignedIn(_):
            break
            
        case .owningUserCreated:
            break
            
        case .sharingUserCreated:
            break
        }
        
        setSignInTypeState()
    }
}

extension ViewController : SyncServerDelegate {
    func shouldSaveDownloads(downloads: [(downloadedFile: NSURL, downloadedFileAttributes: SyncAttributes)]) {
        assert(false)
    }
    
    func syncServerEventOccurred(event: SyncEvent) {
        syncServerEventOccurred?(event)
    }
    
    func shouldDoDeletions(downloadDeletions: [SyncAttributes]) {
        assert(false)
    }
    
    func syncServerErrorOccurred(error:Error) {
        assert(false)
    }
    
    func syncServerSingleFileUploadCompleted(next: @escaping ()->()) {
        syncServerSingleFileUploadCompleted?()
        next()
    }
    
    func syncServerSingleFileDownloadCompleted(next: @escaping ()->()) {
        assert(false)
    }
    
    func uploadDeletion(fileToDelete:ServerAPI.FileToDelete, masterVersion:MasterVersionInt) {
        assert(false)
    }
}


