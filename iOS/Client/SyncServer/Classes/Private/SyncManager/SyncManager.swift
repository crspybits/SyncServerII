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
    weak var delegate:SyncServerDelegate?

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
            case .fileDownloaded(let url, let attr):
                EventDesired.reportEvent(.singleFileDownloadComplete(url:url, attr:attr), mask: self.desiredEvents, delegate: self.delegate)

                func after() {
                    // Recursively (hopefully, this is tail recursion with optimization) check for any next download.
                    self.start(callback)
                }
                
#if DEBUG
                if self.delegate == nil {
                    after()
                }
                else {
                    Thread.runSync(onMainThread: {
                        self.delegate!.syncServerSingleFileDownloadCompleted(next: {
                            after()
                        })
                    })
                }
#else
                after()
#endif
            case .masterVersionUpdate:
                // Need to start all over again.
                self.start(callback)
                
            case .error(let error):
                callback?(StartError.error(error))
            }
        }
        
        switch nextResult {
        case .noDownloadsOrDeletions:
            checkForDownloads()

        case .error(let error):
            callback?(StartError.error(error))
            
        case .started:
            // Don't do anything. `next` completion will invoke callback.
            return
            
        case .allDownloadsCompleted:
            // Inform client via delegate of file downloads and/or download deletions.

            var downloads = [(downloadedFile: NSURL, downloadedFileAttributes: SyncAttributes)]()
            CoreData.sessionNamed(Constants.coreDataName).performAndWait() {
                let dfts = DownloadFileTracker.fetchAll()
                let numberDfts = dfts.count
                assert(numberDfts > 0)
                
                self.fileDownloadDfts = dfts.filter {$0.deletedOnServer == false}
                self.downloadDeletionDfts = dfts.filter {$0.deletedOnServer == true}
                
                if self.fileDownloadDfts!.count > 0 {
                    _ = self.fileDownloadDfts!.map { dft in
                        var attr = SyncAttributes(fileUUID: dft.fileUUID, mimeType: dft.mimeType!, creationDate: dft.creationDate! as Date, updateDate: dft.updateDate! as Date)
                        attr.appMetaData = dft.appMetaData
                        downloads += [(downloadedFile: dft.localURL! as NSURL, downloadedFileAttributes: attr)]
                    }
                }
            }
            
            if downloads.count > 0 {
                Thread.runSync(onMainThread: {
                    self.delegate?.shouldSaveDownloads(downloads: downloads)
                })
                
                CoreData.sessionNamed(Constants.coreDataName).performAndWait() {
                    Directory.session.updateAfterDownloadingFiles(downloads: self.fileDownloadDfts!)
                }
                
                EventDesired.reportEvent(.fileDownloadsCompleted(numberOfFiles: downloads.count), mask: self.desiredEvents, delegate: self.delegate)
            }
            
            var deletions = [SyncAttributes]()
            CoreData.sessionNamed(Constants.coreDataName).performAndWait() {
                if self.downloadDeletionDfts!.count > 0 {
                    _ = self.downloadDeletionDfts!.map { dft in
                        let attr = SyncAttributes(fileUUID: dft.fileUUID, mimeType: dft.mimeType!, creationDate: dft.creationDate! as Date, updateDate: dft.updateDate! as Date)
                        deletions += [attr]
                    }
                    
                    Log.msg("Deletions: count: \(deletions.count)")
                }
            }
            
            // This is broken out of the above `performAndWait` to not get a deadlock when I do the `Thread.runSync(onMainThread:`.
            if deletions.count > 0 {
                Thread.runSync(onMainThread: {
                    self.delegate?.shouldDoDeletions(downloadDeletions: deletions)
                })
                
                CoreData.sessionNamed(Constants.coreDataName).performAndWait() {
                    Directory.session.updateAfterDownloadDeletingFiles(deletions: self.downloadDeletionDfts!)
                }
                
                EventDesired.reportEvent(.downloadDeletionsCompleted(numberOfFiles: deletions.count), mask: self.desiredEvents, delegate: self.delegate)
                
                // TODO: *0* Next, if we have any pending deletions in upload queue for any of these just obtained download deletions, we should remove those pending deletions.
            }
            
            var errorResult:Error?
            CoreData.sessionNamed(Constants.coreDataName).performAndWait() {
                self.numberFileDownloads = self.fileDownloadDfts == nil ? 0 : self.fileDownloadDfts!.count
                self.numberDownloadDeletions = self.downloadDeletionDfts == nil ? 0 : self.downloadDeletionDfts!.count
                
                DownloadFileTracker.removeAll()
                
                do {
                    try CoreData.sessionNamed(Constants.coreDataName).context.save()
                } catch (let error) {
                    errorResult = error
                    return
                }
            }
            
            guard errorResult == nil else {
                callback?(errorResult)
                return
            }
            
            self.checkForPendingUploads()
        }
    }

    // No DownloadFileTracker's queued up. Check the FileIndex to see if there are pending downloads on the server.
    private func checkForDownloads() {
        Download.session.check() { checkCompletion in
            switch checkCompletion {
            case .noDownloadsOrDeletionsAvailable:
                self.checkForPendingUploads()
                
            case .downloadsOrDeletionsAvailable(numberOfFiles: _):
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
            case .fileUploaded(let uft):
                let attr = SyncAttributes(fileUUID: uft.fileUUID, mimeType:uft.mimeType!, creationDate: uft.creationDate! as Date, updateDate: uft.updateDate! as Date)
                EventDesired.reportEvent(.singleFileUploadComplete(attr: attr), mask: self.desiredEvents, delegate: self.delegate)
                
                func after() {
                    // Recursively see if there is a next upload to do.
                    self.checkForPendingUploads()
                }
                
#if DEBUG
                if self.delegate == nil {
                    after()
                }
                else {
                    Thread.runSync(onMainThread: {
                        self.delegate!.syncServerSingleFileUploadCompleted(next: {
                            after()
                        })
                    })
                }
#else
                after()
#endif
            case .uploadDeletion(let fileUUID):
                EventDesired.reportEvent(.singleUploadDeletionComplete(fileUUID: fileUUID), mask: self.desiredEvents, delegate: self.delegate)
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
            case .masterVersionUpdate:
                self.checkForDownloads()
                
            case .error(let error):
                self.callback?(StartError.error(error))
                
            // `numTransferred` may not be accurrate in the case of retries/recovery.
            case .doneUploads(numberTransferred: _):
                var uploadQueue:UploadQueue!
                var fileUploads:[UploadFileTracker]!
                var uploadDeletions:[UploadFileTracker]!
                
                CoreData.sessionNamed(Constants.coreDataName).performAndWait() {
                    uploadQueue = Upload.getHeadSyncQueue()!
                    fileUploads = uploadQueue.uploadFileTrackers.filter {!$0.deleteOnServer}
                }
                
                if fileUploads.count > 0 {
                    EventDesired.reportEvent(.fileUploadsCompleted(numberOfFiles: fileUploads.count), mask: self.desiredEvents, delegate: self.delegate)
                }
                
                CoreData.sessionNamed(Constants.coreDataName).performAndWait() {
                    if fileUploads.count > 0 {
                        // Each of the DirectoryEntry's for the uploads needs to now be given its version, as uploaded.
                        _ = fileUploads.map {uft in
                            guard let uploadedEntry = DirectoryEntry.fetchObjectWithUUID(uuid: uft.fileUUID) else {
                                assert(false)
                                return
                            }

                            uploadedEntry.fileVersion = uft.fileVersion
                        }
                    }
                    
                    uploadDeletions = uploadQueue.uploadFileTrackers.filter {$0.deleteOnServer}
                }

                if uploadDeletions.count > 0 {
                    EventDesired.reportEvent(.uploadDeletionsCompleted(numberOfFiles: uploadDeletions.count), mask: self.desiredEvents, delegate: self.delegate)
                }
                
                var errorResult:Error?
                CoreData.sessionNamed(Constants.coreDataName).performAndWait() {
                    if uploadDeletions.count > 0 {
                        // Each of the DirectoryEntry's for the uploads needs to now be marked as deleted.
                        _ = uploadDeletions.map { uft in
                            guard let uploadedEntry = DirectoryEntry.fetchObjectWithUUID(uuid: uft.fileUUID) else {
                                assert(false)
                                return
                            }

                            uploadedEntry.deletedOnServer = true
                        }
                    }
                    
                    CoreData.sessionNamed(Constants.coreDataName).remove(uploadQueue)
                    
                    do {
                        try CoreData.sessionNamed(Constants.coreDataName).context.save()
                    } catch (let error) {
                        errorResult = error
                        return
                    }
                }
                
                self.callback?(errorResult)
            }
        }
    }
}

