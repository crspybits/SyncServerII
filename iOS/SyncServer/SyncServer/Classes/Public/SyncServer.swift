//
//  SyncServer.swift
//  SyncServer
//
//  Created by Christopher Prince on 2/23/17.
//
//

import Foundation
import SMCoreLib

// TODO: *1* These delegate methods are called on the main thread.

// This information is for testing purposes and for UI (e.g., for displaying download progress).
public enum SyncEvent {
    // The url/attr here may not be consistent with the results from shouldSaveDownloads in the SyncServerDelegate.
    case singleDownloadComplete(url:SMRelativeLocalURL, attr: SyncAttributes)
    case fileDownloadsCompleted(numberOfFiles:Int)
    case downloadDeletionsCompleted(numberOfFiles:Int)
    
    case singleUploadComplete(attr:SyncAttributes)
    case fileUploadsCompleted(numberOfFiles:Int)
    case uploadDeletionsCompleted(numberOfFiles:Int)
    
    case syncDone
}

public struct EventDesired: OptionSet {
    public let rawValue: Int
    public init(rawValue:Int){ self.rawValue = rawValue}

    public static let singleDownloadComplete = EventDesired(rawValue: 1 << 0)
    public static let fileDownloadsCompleted = EventDesired(rawValue: 1 << 1)
    public static let downloadDeletionsCompleted = EventDesired(rawValue: 1 << 2)
    
    public static let singleUploadComplete = EventDesired(rawValue: 1 << 4)
    public static let fileUploadsCompleted = EventDesired(rawValue: 1 << 3)
    public static let uploadDeletionsCompleted = EventDesired(rawValue: 1 << 5)
    
    public static let syncDone = EventDesired(rawValue: 1 << 6)
    
    public static let defaults:EventDesired =
        [.singleDownloadComplete, .fileDownloadsCompleted, .downloadDeletionsCompleted,
        .fileUploadsCompleted, .singleUploadComplete, .uploadDeletionsCompleted]
    public static let all:EventDesired = EventDesired.defaults.union(EventDesired.syncDone)
    
    static func reportEvent(_ event:SyncEvent, mask:EventDesired, delegate:SyncServerDelegate?) {
    
        var eventIsDesired:EventDesired
        
        switch event {
        case .downloadDeletionsCompleted(_):
            eventIsDesired = .downloadDeletionsCompleted
            
        case .fileDownloadsCompleted(_):
            eventIsDesired = .fileDownloadsCompleted

        case .fileUploadsCompleted(_):
            eventIsDesired = .fileUploadsCompleted
            
        case .singleDownloadComplete(_):
            eventIsDesired = .singleDownloadComplete
            
        case .uploadDeletionsCompleted(_):
            eventIsDesired = .uploadDeletionsCompleted
            
        case .syncDone:
            eventIsDesired = .syncDone
            
        case .singleUploadComplete(_):
            eventIsDesired = .singleUploadComplete
        }
        
        if mask.contains(eventIsDesired) {
            delegate?.syncServerEventOccurred(event: event)
        }
    }
}

public protocol SyncServerDelegate : class {
    /* Called at the end of all downloads, on non-error conditions. Only called when there was at least one download.
    The client owns the files referenced by the NSURL's after this call completes. These files are temporary in the sense that they will not be backed up to iCloud, could be removed when the device or app is restarted, and should be moved to a more permanent location. This is received/called in an atomic manner: This reflects the current state of files on the server.
    Client should replace their existing data with that from the files.
    */
    func shouldSaveDownloads(downloads: [(downloadedFile: NSURL, downloadedFileAttributes: SyncAttributes)])

    // Called when deletions have been received from the server. I.e., these files have been deleted on the server. This is received/called in an atomic manner: This reflects a snapshot state of files on the server. Clients should delete the files referenced by the SMSyncAttributes's (i.e., the UUID's).
    func shouldDoDeletions(downloadDeletions downloadDeletions:[SyncAttributes])
    
    func syncServerErrorOccurred(error:Error)

    // Reports events. Useful for testing and UI.
    func syncServerEventOccurred(event:SyncEvent)
}

public class SyncServer {
    public static let session = SyncServer()
    private var syncOperating = false
    private var delayedSync = false
    
    private init() {
    }
    
    public var eventsDesired:EventDesired {
        set {
            SyncManager.session.desiredEvents = newValue
        }
        
        get {
            return SyncManager.session.desiredEvents
        }
    }
    
    public weak var delegate:SyncServerDelegate? {
        set {
            SyncManager.session.delegate = newValue
        }
        
        get {
            return SyncManager.session.delegate
        }
    }
    
    public func appLaunchSetup(withServerURL serverURL: URL, cloudFolderName:String) {
    
        Upload.session.cloudFolderName = cloudFolderName
        
        Network.session().detect { connected in
            if connected {
                self.networkReconnected()
            }
        }
        
        Network.session().appStartup()

        ServerAPI.session.baseURL = serverURL.absoluteString

        // This seems a little hacky, but can't find a better way to get the bundle of the framework containing our model. I.e., "this" framework. Just using a Core Data object contained in this framework to track it down.
        // Without providing this bundle reference, I wasn't able to dynamically locate the model contained in the framework.
        let bundle = Bundle(for: NSClassFromString(Singleton.entityName())!)
        
        let coreDataSession = CoreData(namesDictionary: [
            CoreDataModelBundle: bundle,
            CoreDataBundleModelName: "Client",
            CoreDataSqlliteBackupFileName: "~Client.sqlite",
            CoreDataSqlliteFileName: "Client.sqlite"
        ]);
        
        CoreData.registerSession(coreDataSession, forName: Constants.coreDataName)
    }
    
    public enum SyncClientAPIError: Error {
    case mimeTypeOfFileChanged
    case fileAlreadyDeleted
    }
    
    // Enqueue a local immutable file for subsequent upload. Immutable files are assumed to not change (at least until after the upload has completed). This immutable characteristic is not enforced by this class but needs to be enforced by the caller of this class.
    // This operation survives app launches, as long as the the call itself completes. 
    // If there is a file with the same uuid, which has been enqueued for upload but not yet `sync`'ed, it will be replaced by the given file. 
    // This operation does not access the server, and thus runs quickly and synchronously.
    public func uploadImmutable(localFile:SMRelativeLocalURL, withAttributes attr: SyncAttributes) throws {
        try upload(fileURL: localFile, withAttributes: attr)
    }
    
    private func upload(fileURL:SMRelativeLocalURL, withAttributes attr: SyncAttributes) throws {
        var entry = DirectoryEntry.fetchObjectWithUUID(uuid: attr.fileUUID)
        
        if nil == entry {
            entry = DirectoryEntry.newObject() as! DirectoryEntry
            entry!.fileUUID = attr.fileUUID
            entry!.mimeType = attr.mimeType
        }
        else {
            if entry!.fileVersion != nil {
                // Right now, we're not allowing uploads of multiple version files, so this is not allowed.
                // When we can do upload deletions, we'll enable this too, but still you will only be able to delete version 0 of the file.
                assert(false)
            }
            
            if attr.mimeType != entry!.mimeType {
                throw SyncClientAPIError.mimeTypeOfFileChanged
            }
            
            if entry!.deletedOnServer {
                throw SyncClientAPIError.fileAlreadyDeleted
            }
        }
        
        let newUft = UploadFileTracker.newObject() as! UploadFileTracker
        newUft.localURL = fileURL
        newUft.appMetaData = attr.appMetaData
        newUft.fileUUID = attr.fileUUID
        newUft.mimeType = attr.mimeType
        
        if entry!.fileVersion == nil {
            newUft.fileVersion = 0
        }
        else {
            newUft.fileVersion = entry!.fileVersion! + 1
        }
        
        // Has this file UUID been added to `pendingSync` already? i.e., Has the client called `uploadImmutable`, then a little later called `uploadImmutable` again, with the same uuid, all without calling `sync`-- so, we don't have a new file version because new file versions only occur once the upload hits the server.
        let result = Upload.pendingSync().uploadFileTrackers.filter {$0.fileUUID == attr.fileUUID}
        if result.count > 0 {
            result.map { uft in
                CoreData.sessionNamed(Constants.coreDataName).remove(uft)
            }
        }
        
        Upload.pendingSync().addToUploads(newUft)
        CoreData.sessionNamed(Constants.coreDataName).saveContext()
    }
    
    // If no other `sync` is taking place, this will asynchronously do pending downloads and uploads. If there is a `sync` currently taking place, this will wait until after that is done, and try again.
    public func sync() {
        var doStart = true
        
        Synchronized.block(self) {
            if Upload.pendingSync().uploadFileTrackers.count > 0  {
                Upload.movePendingSyncToSynced()
            }
            
            if syncOperating {
                delayedSync = true
                doStart = false
            }
            else {
                syncOperating = true
            }
        }
        
        if doStart {
            start()
        }
    }
    
    private func start() {
        Log.msg("SyncServer.start")
        SyncManager.session.start { error in
            if error != nil {
                self.delegate?.syncServerErrorOccurred(error: error!)
            }
            
            EventDesired.reportEvent(.syncDone, mask: self.eventsDesired, delegate: self.delegate)

            var doStart = false
            
            Synchronized.block(self) {
                if Upload.haveSyncQueue()  || self.delayedSync {
                    self.delayedSync = false
                    doStart = true
                }
                else {
                    self.syncOperating = false
                }
            }
            
            if doStart {
                self.start()
            }
        }
    }
    
    private func networkReconnected() {
        let dfts = DownloadFileTracker.fetchAll()
        dfts.map { dft in
            if dft.status == .downloading {
                dft.status = .notStarted
            }
        }
        
        Upload.pendingSync().uploadFileTrackers.map { uft in
            if uft.status == .uploading {
                uft.status = .notStarted
            }
        }
        
        CoreData.sessionNamed(Constants.coreDataName).saveContext()
    }
}
