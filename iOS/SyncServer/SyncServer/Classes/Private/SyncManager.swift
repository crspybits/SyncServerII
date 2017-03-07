//
//  SyncManager.swift
//  SyncServer
//
//  Created by Christopher Prince on 2/26/17.
//
//

import Foundation
import SMCoreLib

class SyncManager {
    static let session = SyncManager()
    public weak var delegate:SyncServerDelegate?

    private var fileDownloadDfts:[DownloadFileTracker]?
    private var downloadDeletionDfts:[DownloadFileTracker]?
    private var numberFileDownloads = 0
    private var numberDownloadDeletions = 0
    private var callback:((Error?)->())?
    var desiredEvents:EventDesired = .defaults

    private init() {
    }
    
    enum StartError : Error {
    case error(String)
    }
    
    // TODO: *1* If we get an app restart when we call this method, and an upload was previously in progress, and we now have download(s) available, we need to reset those uploads prior to doing the downloads.
    func start(_ callback:((Error?)->())? = nil) {
        self.callback = callback
        
        // TODO: *1* This is probably the level at which we should ensure that multiple download operations are not taking place concurrently. E.g., some locking mechanism?
        
        // First: Do we have previously queued downloads that need to be downloaded?
        let nextResult = Download.session.next() { nextCompletionResult in
            switch nextCompletionResult {
            case .downloaded(let dft):
                let attr = SyncAttributes(fileUUID: dft.fileUUID, mimeType:dft.mimeType!)
                EventDesired.reportEvent(.singleDownloadComplete(url:dft.localURL!, attr:attr), mask: self.desiredEvents, delegate: self.delegate)
            
                // Recursively (hopefully, this is tail recursion with optimization) check for any next download.
                self.start(callback)
                return
                
            case .masterVersionUpdate:
                // Need to start all over again.
                self.start(callback)
                return
                
            case .error(let error):
                callback?(StartError.error(error))
                return
            }
        }
        
        switch nextResult {
        case .started:
            // Don't do anything. `next` completion will invoke callback.
            return
            
        case .allDownloadsCompleted:
            // Inform client via delegate of file downloads and/or download deletions.
            
            let dfts = DownloadFileTracker.fetchAll()
            let numberDfts = dfts.count
            assert(numberDfts > 0)
            
            fileDownloadDfts = dfts.filter {$0.deletedOnServer == false}
            downloadDeletionDfts = dfts.filter {$0.deletedOnServer == true}
            
            if fileDownloadDfts!.count > 0 {
                var downloads = [(downloadedFile: NSURL, downloadedFileAttributes: SyncAttributes)]()
                fileDownloadDfts!.map { dft in
                    let attr = SyncAttributes(fileUUID: dft.fileUUID, mimeType: dft.mimeType!)
                    downloads += [(downloadedFile: dft.localURL! as NSURL, downloadedFileAttributes: attr)]
                }
            
                delegate?.shouldSaveDownloads(downloads: downloads)
                Directory.session.updateAfterDownloadingFiles(downloads: fileDownloadDfts!)
                EventDesired.reportEvent(.fileDownloadsCompleted(numberOfFiles: fileDownloadDfts!.count), mask: self.desiredEvents, delegate: self.delegate)
            }
            
            if downloadDeletionDfts!.count > 0 {
                var deletions = [SyncAttributes]()
                downloadDeletionDfts!.map { dft in
                    let attr = SyncAttributes(fileUUID: dft.fileUUID, mimeType: dft.mimeType!)
                    deletions += [attr]
                }
                
                Log.msg("Deletions: count: \(deletions.count)")
                
                delegate?.shouldDoDeletions(downloadDeletions: deletions)
                Directory.session.updateAfterDownloadDeletingFiles(deletions: downloadDeletionDfts!)
                EventDesired.reportEvent(.downloadDeletionsCompleted(numberOfFiles: downloadDeletionDfts!.count), mask: self.desiredEvents, delegate: self.delegate)
                // TODO: *0* Next, if we have any pending deletions in upload queue for any of these just obtained download deletions, we should remove those pending deletions.
            }
            
            numberFileDownloads = fileDownloadDfts == nil ? 0 : fileDownloadDfts!.count
            numberDownloadDeletions = downloadDeletionDfts == nil ? 0 : downloadDeletionDfts!.count
            
            DownloadFileTracker.removeAll()
            CoreData.sessionNamed(Constants.coreDataName).saveContext()
            self.checkForPendingUploads()
            
        case .noDownloadsOrDeletions:
            checkForDownloads()

        case .error(let error):
            callback?(StartError.error(error))
        }
    }

    // No DownloadFileTracker's queued up. Check the FileIndex to see if there are pending downloads on the server.
    private func checkForDownloads() {
        Download.session.check() { checkCompletion in
            switch checkCompletion {
            case .noDownloadsOrDeletionsAvailable:
                self.checkForPendingUploads()
                
            case .downloadsOrDeletionsAvailable(numberOfFiles: let numDownloads):
                // We've got DownloadFileTracker's queued up now. Go deal with them!
                self.start(self.callback)
                
            case .error(let error):
                self.callback?(error)
            }
        }
    }
    
    private func checkForPendingUploads() {
        let nextResult = Upload.session.next { nextCompletion in
            switch nextCompletion {
            case .uploaded(let uft):
                let attr = SyncAttributes(fileUUID: uft.fileUUID, mimeType:uft.mimeType!)
                EventDesired.reportEvent(.singleUploadComplete(attr: attr), mask: self.desiredEvents, delegate: self.delegate)
                // Recursively see if there is a next upload to do.
                self.checkForPendingUploads()

            case .masterVersionUpdate:
                // Things have changed on the server. Check for downloads again. Don't go all the way back to `start` because we know that we don't have queued downloads.
                self.checkForDownloads()
                
            case .error(let error):
                self.callback?(StartError.error(error))
            }
        }
        
        switch nextResult {
        case .started:
            // Don't do anything. `next` completion will invoke callback.
            break
            
        case .noUploads:
            callback?(nil)
            
        case .allUploadsCompleted:
            self.doneUploads()
            
        case .error(let error):
            callback?(StartError.error(error))
        }
    }
    
    private func doneUploads() {
        Upload.session.doneUploads { completionResult in
            switch completionResult {
            case .doneUploads(numberTransferred: let numTransferred):
                let uploadQueue = Upload.getHeadSyncQueue()!
                
                let fileUploads = uploadQueue.uploadFileTrackers.filter {!$0.deleteOnServer}
                if fileUploads.count > 0 {
                    EventDesired.reportEvent(.fileUploadsCompleted(numberOfFiles: fileUploads.count), mask: self.desiredEvents, delegate: self.delegate)
                    
                    // Each of the DirectoryEntry's for the uploads needs to now be given its version, as uploaded.
                    fileUploads.map {uft in
                        guard let uploadedEntry = DirectoryEntry.fetchObjectWithUUID(uuid: uft.fileUUID) else {
                            assert(false)
                        }

                        uploadedEntry.fileVersion = uft.fileVersion
                    }
                }
                
                CoreData.sessionNamed(Constants.coreDataName).remove(uploadQueue)
                CoreData.sessionNamed(Constants.coreDataName).saveContext()
                self.callback?(nil)
                
            case .masterVersionUpdate:
                self.checkForDownloads()
                
            case .error(let error):
                self.callback?(StartError.error(error))
            }
        }
    }
}

