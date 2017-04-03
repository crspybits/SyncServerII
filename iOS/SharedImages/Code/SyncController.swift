//
//  SyncController.swift
//  SharedImages
//
//  Created by Christopher Prince on 3/12/17.
//  Copyright © 2017 Spastic Muffin, LLC. All rights reserved.
//

import Foundation
import SyncServer
import SMCoreLib

enum SyncControllerEvent {
    case syncStarted
    case syncDone
    case syncError
}

protocol SyncControllerDelegate : class {
    func addLocalImage(syncController:SyncController, url:SMRelativeLocalURL, uuid:String, mimeType:String)
    func removeLocalImage(syncController:SyncController, uuid:String)
    func syncEvent(syncController:SyncController, event:SyncControllerEvent)
}

class SyncController {
    init() {
        SyncServer.session.delegate = self
        SyncServer.session.eventsDesired = [EventDesired.syncStarted, EventDesired.syncDone]
    }
    
    weak var delegate:SyncControllerDelegate!
    
    func sync() {
        SyncServer.session.sync()
    }
    
    func add(image:Image) {
        let attr = SyncAttributes(fileUUID:image.uuid!, mimeType:image.mimeType!)
        
        do {
            try SyncServer.session.uploadImmutable(localFile: image.url!, withAttributes: attr)
            SyncServer.session.sync()
        } catch (let error) {
            Log.error("An error occurred: \(error)")
        }
    }
    
    func remove(image:Image) {
        do {
            try SyncServer.session.delete(fileWithUUID: image.uuid!)
            SyncServer.session.sync()
        } catch (let error) {
            Log.error("An error occurred: \(error)")
        }
    }
}

extension SyncController : SyncServerDelegate {
    func shouldSaveDownloads(downloads: [(downloadedFile: NSURL, downloadedFileAttributes: SyncAttributes)]) {
        for download in downloads {
            let url = FileExtras().newURLForImage()
            
            // The files we get back from the SyncServer are in a temporary location.
            do {
                try FileManager.default.moveItem(at: download.downloadedFile as URL, to: url as URL)
            } catch (let error) {
                Log.error("An error occurred moving a file: \(error)")
            }
            
            delegate.addLocalImage(syncController: self, url: url, uuid: download.downloadedFileAttributes.fileUUID, mimeType: download.downloadedFileAttributes.mimeType)
        }
    }

    func shouldDoDeletions(downloadDeletions:[SyncAttributes]) {
        for deletion in downloadDeletions {
            delegate.removeLocalImage(syncController: self, uuid: deletion.fileUUID)
        }
    }
    
    func syncServerErrorOccurred(error:Error) {
        Log.error("Server error occurred: \(error)")
        delegate.syncEvent(syncController: self, event: .syncError)
    }

    func syncServerEventOccurred(event:SyncEvent) {
        Log.msg("Server event occurred: \(event)")
        
        switch event {
        case .syncStarted:
            delegate.syncEvent(syncController: self, event: .syncStarted)
            
        case .syncDone:
            delegate.syncEvent(syncController: self, event: .syncDone)
        
        default:
            break
        }
    }
    
#if DEBUG
    public func syncServerSingleFileUploadCompleted(next: @escaping () -> ()) {
        next()
    }
    
    public func syncServerSingleFileDownloadCompleted(next: @escaping () -> ()) {
        next()
    }
#endif
}
