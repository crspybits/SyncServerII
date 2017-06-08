//
//  Download.swift
//  SyncServer
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
    
    enum OnlyCheckCompletion {
    case checkResult(downloadFiles:[FileInfo]?, downloadDeletions:[FileInfo]?, MasterVersionInt?)
    case error(Error)
    }
    
    // TODO: *0* while this check is occurring, we want to make sure we don't have a concurrent check operation.
    // Doesn't create DownloadFileTracker's or update MasterVersion.
    func onlyCheck(completion:((OnlyCheckCompletion)->())? = nil) {
        
        Log.msg("Download.onlyCheckForDownloads")
        
        ServerAPI.session.fileIndex { (fileIndex, masterVersion, error) in
            guard error == nil else {
                completion?(.error(error!))
                return
            }

            var completionResult:OnlyCheckCompletion!
            
            CoreData.sessionNamed(Constants.coreDataName).performAndWait() {
                do {
                    let (downloads, deletions) =
                        try Directory.session.checkFileIndex(fileIndex: fileIndex!)
                    completionResult =
                        .checkResult(downloadFiles:downloads, downloadDeletions:deletions, masterVersion)
                } catch (let error) {
                    completionResult = .error(error)
                }
                
                completion?(completionResult)
            }
        }
    }
    
    enum CheckCompletion {
    case noDownloadsOrDeletionsAvailable
    case downloadsOrDeletionsAvailable(numberOfFiles:Int32)
    case error(Error)
    }
    
    // TODO: *0* while this check is occurring, we want to make sure we don't have a concurrent check operation.
    // Creates DownloadFileTracker's to represent files that need downloading/download deleting. Updates MasterVersion with the master version on the server.
    func check(completion:((CheckCompletion)->())? = nil) {
        onlyCheck() { onlyCheckResult in
            switch onlyCheckResult {
            case .error(let error):
                completion?(.error(error))
            
            case .checkResult(downloadFiles: let fileDownloads, downloadDeletions: let downloadDeletions, let masterVersion):
                
                var completionResult:CheckCompletion!

                CoreData.sessionNamed(Constants.coreDataName).performAndWait() {
                    Singleton.get().masterVersion = masterVersion!
                    
                    if fileDownloads == nil && downloadDeletions == nil {
                        completionResult = .noDownloadsOrDeletionsAvailable
                    }
                    else {
                        let allFiles = (fileDownloads ?? []) + (downloadDeletions ?? [])
                        for file in allFiles {
                            if file.fileVersion != 0 {
                                // TODO: *5* We're considering this an error currently because we're not yet supporting multiple file versions.
                                assert(false, "Not Yet Implemented: Multiple File Versions")
                            }
                            
                            let dft = DownloadFileTracker.newObject() as! DownloadFileTracker
                            dft.fileUUID = file.fileUUID
                            dft.fileVersion = file.fileVersion
                            dft.mimeType = file.mimeType
                            dft.deletedOnServer = file.deleted!
                        }
                        
                        completionResult = .downloadsOrDeletionsAvailable(numberOfFiles: Int32(allFiles.count))
                    }
                    
                    do {
                        try CoreData.sessionNamed(Constants.coreDataName).context.save()
                    } catch (let error) {
                        completionResult = .error(error)
                        return
                    }
                } // End performAndWait
                
                completion?(completionResult)
            }
        }
    }

    enum NextResult {
    case started
    case noDownloadsOrDeletions
    case allDownloadsCompleted
    case error(String)
    }
    
    enum NextCompletion {
    case fileDownloaded(url:SMRelativeLocalURL, attr:SyncAttributes)
    case masterVersionUpdate
    case error(String)
    }
    
    // Starts download of next file, if there is one. There should be no files downloading already. Only if .started is the NextResult will the completion handler be called. With a masterVersionUpdate response for NextCompletion, the MasterVersion Core Data object is updated by this method, and all the DownloadFileTracker objects have been reset.
    func next(completion:((NextCompletion)->())?) -> NextResult {
        var masterVersion:MasterVersionInt!
        var nextResult:NextResult?
        var downloadFile:FilenamingObject!
        var nextToDownload:DownloadFileTracker!
        
        CoreData.sessionNamed(Constants.coreDataName).performAndWait() {
            let dfts = DownloadFileTracker.fetchAll()
            guard dfts.count != 0 else {
                nextResult = .noDownloadsOrDeletions
                return
            }

            let alreadyDownloading = dfts.filter {$0.status == .downloading}
            guard alreadyDownloading.count == 0 else {
                let message = "Already downloading a file!"
                Log.error(message)
                nextResult = .error(message)
                return
            }
            
            let notStarted = dfts.filter {$0.status == .notStarted && !$0.deletedOnServer}
            guard notStarted.count != 0 else {
                nextResult = .allDownloadsCompleted
                return
            }
            
            masterVersion = Singleton.get().masterVersion

            nextToDownload = notStarted[0]
            nextToDownload.status = .downloading
            
            do {
                try CoreData.sessionNamed(Constants.coreDataName).context.save()
            } catch (let error) {
                nextResult = .error("\(error)")
            }
            
            // Need this inside the `performAndWait` to bridge the gap without an NSManagedObject
            downloadFile = FilenamingObject(fileUUID: nextToDownload.fileUUID, fileVersion: nextToDownload.fileVersion)
        }
        
        guard nextResult == nil else {
            return nextResult!
        }

        ServerAPI.session.downloadFile(file: downloadFile, serverMasterVersion: masterVersion) { (result, error)  in
        
            // Don't hold the performAndWait while we do completion-- easy to get a deadlock!

            guard error == nil else {
                CoreData.sessionNamed(Constants.coreDataName).performAndWait() {
                    nextToDownload.status = .notStarted
                    
                    // Not going to check for exceptions on saveContext; we already have an error.
                    CoreData.sessionNamed(Constants.coreDataName).saveContext()
                }
                
                let message = "Error: \(String(describing: error))"
                Log.error(message)
                completion?(.error(message))
                return
            }
            
            switch result! {
            case .success(let downloadedFile):
                var nextCompletionResult:NextCompletion!
                CoreData.sessionNamed(Constants.coreDataName).performAndWait() {
                    nextToDownload.status = .downloaded
                    Log.msg("downloadedFile.appMetaData: \(String(describing: downloadedFile.appMetaData))")
                    nextToDownload.appMetaData = downloadedFile.appMetaData
                    nextToDownload.fileSizeBytes = downloadedFile.fileSizeBytes
                    nextToDownload.localURL = downloadedFile.url
                    
                    do {
                        try CoreData.sessionNamed(Constants.coreDataName).context.save()
                    } catch (let error) {
                        nextCompletionResult = .error("\(error)")
                        return
                    }
                    
                    let url = nextToDownload.localURL
                    var attr = SyncAttributes(fileUUID: nextToDownload.fileUUID, mimeType: nextToDownload.mimeType!)
                    attr.appMetaData = nextToDownload.appMetaData
                    nextCompletionResult = .fileDownloaded(url:url!, attr:attr)
                }
        
                completion?(nextCompletionResult)
                
            case .serverMasterVersionUpdate(let masterVersionUpdate):
                // TODO: *2* A more efficient method (than in place here) is to get the file index, giving us the new masterVersion, and see which files that we have already downloaded have the same version as we expect.
                // The simplest method to deal with this is to restart all downloads. It is insufficient to just reset all of the DownloadFileTracker objects: Because some of the files we're wanting to download could have been marked as deleted in the FileIndex on the server. Thus, I'm going to remove all DownloadFileTracker objects.
                var nextCompletionResult:NextCompletion!
                CoreData.sessionNamed(Constants.coreDataName).performAndWait() {
                    DownloadFileTracker.removeAll()
                    Singleton.get().masterVersion = masterVersionUpdate
                    
                    do {
                        try CoreData.sessionNamed(Constants.coreDataName).context.save()
                    } catch (let error) {
                        nextCompletionResult = .error("\(error)")
                        return
                    }
                    
                    nextCompletionResult = .masterVersionUpdate
                }
                
                completion?(nextCompletionResult)
            }
        }
        
        return .started
    }
}
