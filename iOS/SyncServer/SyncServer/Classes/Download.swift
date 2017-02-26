//
//  Download.swift
//  Pods
//
//  Created by Christopher Prince on 2/23/17.
//
//

import Foundation
import SMCoreLib

class Download {
    static let session = Download()
    
    private init() {
    }
    
    /* A download consists of:
        a) Doing a FileIndex
        b) Checking that FileIndex against our local directory of files to see
            if we need to do any downloads
        c) If yes, then creating persistent Core Data objects for each of those
            files-to-be-downloaded so that if we lose power etc. we can restart downloads.
        d) We also need to record the masterVersion on the server persistently.
        e) Next, download each file.
            On each download, if the masterVersion gets updated, we need to restart
            the process.
        f) With all files downloaded and masterVersion unchanged, we can
            call the client's delegate method.
    */
    
    // TODO: *0* while this check is occuring, we want to make sure we don't have a concurrent check operation.
    func check(completion:((Error?)->())? = nil) {
        ServerAPI.session.fileIndex { (fileIndex, masterVersion, error) in
            guard error == nil else {
                completion?(error)
                return
            }

            // TODO: *1* Deal with download deletions.
            let (fileDownloads, _) = Directory.session.checkFileIndex(fileIndex: fileIndex!)
            
            if fileDownloads != nil {
                for file in fileDownloads! {
                    if file.fileVersion != 0 {
                        // TODO: *5* We're considering this an error currently because we're not yet supporting multiple file versions.
                        assert(false, "Not Yet Implemented: Multiple File Versions")
                    }
                    
                    let dft = DownloadFileTracker.newObject() as! DownloadFileTracker
                    dft.fileUUID = file.fileUUID
                    dft.fileVersion = file.fileVersion
                }
                
                MasterVersion.get().version = masterVersion!
                
                CoreData.sessionNamed(Constants.coreDataName).saveContext()
            }
            
            completion?(nil)
        }
    }
    
    func next() {
    }
}
