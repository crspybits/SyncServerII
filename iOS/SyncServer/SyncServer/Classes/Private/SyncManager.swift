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

    private init() {
    }
    
    enum ProcessError : Error {
    case nextError(String)
    }
    
    // This is just informative; for testing purposes.
    enum StartResult {
    case shouldSaveDownloadsCalled(numberFiles: Int)
    case noDownloadsAvailable
    }
    
    func start(_ callback:((StartResult?, Error?)->())? = nil) {
        // TODO: *1* This is probably the level at which we should ensure that multiple download operations are not taking place concurrently. E.g., some locking mechanism?
        
        // First: Do we have previously queued downloads that need to be downloaded?
        let nextResult = Download.session.next() { nextCompletionResult in
            switch nextCompletionResult {
            case .downloaded(let dft):
                let attr = SyncAttributes(fileUUID: dft.fileUUID, fileVersion: dft.fileVersion)
                self.delegate?.syncServerEventOccurred(event: .singleDownloadComplete(url:dft.localURL!, attr:attr))
            
                // Recursively (hopefully, this is tail recursion with optimization) check for any next download.
                self.start(callback)
                return
                
            case .masterVersionUpdate:
                // Need to start all over again.
                self.start(callback)
                return
                
            case .error(let error):
                callback?(nil, ProcessError.nextError(error))
                return
            }
        }
        
        switch nextResult {
        case .started:
            // Don't do anything. `next` completion will invoke callback.
            return
            
        case .allDownloadsCompleted:
            // Inform client via delegate of downloads.
            
            let dfts = DownloadFileTracker.fetchAll()
            let numberDfts = dfts.count
            assert(numberDfts > 0)
            
            var downloads = [(downloadedFile: NSURL, downloadedFileAttributes: SyncAttributes)]()
            dfts.map { dft in
                let attr = SyncAttributes(fileUUID: dft.fileUUID, fileVersion: dft.fileVersion)
                downloads += [(downloadedFile: dft.localURL! as NSURL, downloadedFileAttributes: attr)]
            }
            
            delegate?.syncServerShouldSaveDownloads(downloads: downloads, next: {
                // Client has saved the files-- we can update Core Data to reflect these downloads.
                
                Directory.session.updateAfterDownloadingFiles(dfts: dfts)
                DownloadFileTracker.removeAll()
                CoreData.sessionNamed(Constants.coreDataName).saveContext()
                
                callback?(.shouldSaveDownloadsCalled(numberFiles: numberDfts), nil)
            })
            
        case .noDownloads:
            Download.session.check() { checkCompletion in
                switch checkCompletion {
                case .noDownloadsAvailable:
                    // TODO: *3* Later, when we're dealing with uploads, this will go on to check to see if we have pending uploads.
                    callback?(.noDownloadsAvailable, nil)
                    
                case .downloadsAvailable(numberOfDownloads: let numDownloads):
                    self.start(callback)
                    return
                    
                case .error(let error):
                    callback?(nil, error)
                }
            }

        case .error(let error):
            callback?(nil, ProcessError.nextError(error))
        }
    }
}
