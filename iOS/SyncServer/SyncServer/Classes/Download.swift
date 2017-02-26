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
    
    // TODO: *0* while this check is occuring, we want to make sure we don't have a concurrent check operation.
    // Creates DirectoryEntry's as neeed to represent files in FileIndex on server, but not known about locally. Creates DownloadFileTracker's to represent files that need downloading. Updates MasterVersion with the master version on the server.
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

    /* A download consists of:

        e) Next, download each file.
            On each download, if the masterVersion gets updated, we need to restart
            the process.
        f) With all files downloaded and masterVersion unchanged, we can
            call the client's delegate method.
    */
    enum NextResult {
    case startedDownload
    case noDownloads
    case allDownloadsCompleted
    case error(String)
    }
    
    enum NextCompletion {
    case downloaded
    case masterVersionUpdate
    case error(String)
    }
    
    // Starts download of next file, if there is one. There should be no files downloading already. Only if .startedDownload is the NextResult will the completion handler be called.
    func next(completion:((NextCompletion)->())?) -> NextResult {
        let dfts = DownloadFileTracker.fetchAll()
        if dfts.count == 0 {
            return .noDownloads
        }

        let alreadyDownloading = dfts.filter {$0.status == .downloading}
        if alreadyDownloading.count != 0 {
            return .error("Already downloading a file!")
        }
        
        let notStarted = dfts.filter {$0.status == .notStarted}
        if notStarted.count == 0 {
            return .allDownloadsCompleted
        }
        
        let nextToDownload = notStarted[0]

        let masterVersion = MasterVersion.get().version
        ServerAPI.session.downloadFile(file: nextToDownload as! Filenaming, serverMasterVersion: masterVersion) { (result, error)  in
            guard error == nil else {
                Synchronized.block(nextToDownload) {
                    nextToDownload.status = .notStarted
                    CoreData.sessionNamed(Constants.coreDataName).saveContext()
                }
                
                let message = "Error: \(error)"
                Log.error(message)
                completion?(.error(message))
                return
            }
            
            switch result! {
            case .success(let downloadedFile):
                Synchronized.block(nextToDownload) {
                    nextToDownload.status = .downloaded
                    nextToDownload.appMetaData = downloadedFile.appMetaData
                    nextToDownload.fileSizeBytes = downloadedFile.fileSizeBytes
                    nextToDownload.localURL = downloadedFile.url
                    CoreData.sessionNamed(Constants.coreDataName).saveContext()
                }
                completion?(.downloaded)
                
            case .serverMasterVersionUpdate(let masterVersionUpdate):
                Synchronized.block(nextToDownload) {
                    // The simplest method to deal with this is to restart all downloads. 
                    // TODO: *2* A more efficient method is to get the file index, giving us the new masterVersion, and see which files that we have already downloaded have the same version as we expect.
                    dfts.map { dft in
                        dft.reset()
                    }
                    MasterVersion.get().version = masterVersionUpdate
                    CoreData.sessionNamed(Constants.coreDataName).saveContext()
                }
                completion?(.masterVersionUpdate)
            }
        }
        
        Synchronized.block(nextToDownload) {
            nextToDownload.status = .downloading
            CoreData.sessionNamed(Constants.coreDataName).saveContext()
        }
        
        return .startedDownload
    }
}
