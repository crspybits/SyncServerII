//
//  Upload.swift
//  SyncServer
//
//  Created by Christopher Prince on 2/28/17.
//
//

import Foundation
import SMCoreLib

class Upload {
    static let session = Upload()
    var cloudFolderName:String!
    var deviceUUID:String!
    private var completion:((NextCompletion)->())?
    
    private init() {
    }
    
    enum NextResult {
    case started
    case noUploads
    case allUploadsCompleted
    case error(String)
    }
    
    enum NextCompletion {
    case fileUploaded(UploadFileTracker)
    case uploadDeletion(UploadFileTracker)
    case masterVersionUpdate
    case error(String)
    }
    
    // Starts upload of next file, if there is one. There should be no files uploading already. Only if .started is the NextResult will the completion handler be called. With a masterVersionUpdate response for NextCompletion, the MasterVersion Core Data object is updated by this method, and all the UploadFileTracker objects have been reset.
    func next(completion:((NextCompletion)->())?) -> NextResult {
        self.completion = completion
        
        guard let uploadQueue = Upload.getHeadSyncQueue() else {
            return .noUploads
        }
        
        let alreadyUploading =
            uploadQueue.uploadFileTrackers.filter {$0.status == .uploading}
        if alreadyUploading.count > 0 {
            let message = "Already uploading a file!"
            Log.error(message)
            return .error(message)
        }

        guard let nextToUpload = uploadQueue.nextUpload() else {
            return .allUploadsCompleted
        }

        let masterVersion = Singleton.get().masterVersion

        nextToUpload.status = .uploading
        CoreData.sessionNamed(Constants.coreDataName).saveContext()
        
        if nextToUpload.deleteOnServer {
            uploadDeletion(nextToUpload:nextToUpload, uploadQueue:uploadQueue, masterVersion:masterVersion)
        }
        else {
            uploadFile(nextToUpload: nextToUpload, uploadQueue: uploadQueue, masterVersion: masterVersion)
        }
        
        return .started
    }
    
    private func uploadDeletion(nextToUpload:UploadFileTracker, uploadQueue:UploadQueue, masterVersion:MasterVersionInt) {

        // We need to figure out the current file version for the file we are deleting: Because, as explained in [1] in SyncServer.swift, we didn't establish the file version we were deleting earlier.
        
        guard let entry = DirectoryEntry.fetchObjectWithUUID(uuid: nextToUpload.fileUUID) else {
            self.completion?(.error("Could not find fileUUID: \(nextToUpload.fileUUID)"))
            return
        }
        
        guard entry.fileVersion != nil else {
            self.completion?(.error("File version for fileUUID: \(nextToUpload.fileUUID) was nil!"))
            return
        }
        
        let fileToDelete = ServerAPI.FileToDelete(fileUUID: nextToUpload.fileUUID, fileVersion: entry.fileVersion!)
        
        ServerAPI.session.uploadDeletion(file: fileToDelete, serverMasterVersion: masterVersion) { (uploadDeletionResult, error) in
            guard error == nil else {
                nextToUpload.status = .notStarted
                CoreData.sessionNamed(Constants.coreDataName).saveContext()
                
                let message = "Error: \(error)"
                Log.error(message)
                self.completion?(.error(message))
                return
            }
            
            switch uploadDeletionResult! {
            case .success:
                nextToUpload.status = .uploaded
                CoreData.sessionNamed(Constants.coreDataName).saveContext()
                self.completion?(.uploadDeletion(nextToUpload))
                
            case .serverMasterVersionUpdate(let masterVersionUpdate):
                // Simplest method for now: Mark all uft's as .notStarted
                // TODO: *4* This could be better-- performance-wise, it doesn't make sense to do all the uploads over again.
                uploadQueue.uploadFileTrackers.map { uft in
                    uft.status = .notStarted
                }

                Singleton.get().masterVersion = masterVersionUpdate
                CoreData.sessionNamed(Constants.coreDataName).saveContext()
                self.completion?(.masterVersionUpdate)
            }
        }
    }
    
    private func uploadFile(nextToUpload:UploadFileTracker, uploadQueue:UploadQueue,masterVersion:MasterVersionInt) {
    
        let file = ServerAPI.File(localURL: nextToUpload.localURL! as URL!, fileUUID: nextToUpload.fileUUID, mimeType: nextToUpload.mimeType, cloudFolderName: cloudFolderName, deviceUUID:deviceUUID, appMetaData: nextToUpload.appMetaData, fileVersion: nextToUpload.fileVersion)
        
        ServerAPI.session.uploadFile(file: file, serverMasterVersion: masterVersion) { (uploadResult, error) in
            guard error == nil else {
                nextToUpload.status = .notStarted
                CoreData.sessionNamed(Constants.coreDataName).saveContext()
                
                /* TODO: *0* Need to deal with this error:
                    1) Do retry(s)
                    2) Fail if retries don't work and put the SyncServer client interface into an error state.
                    3) Deal with other, similar, errors too, in a similar way.
                */
                let message = "Error: \(error)"
                Log.error(message)
                self.completion?(.error(message))
                return
            }
 
            switch uploadResult! {
            case .success(sizeInBytes: let sizeInBytes):
                nextToUpload.status = .uploaded
                CoreData.sessionNamed(Constants.coreDataName).saveContext()
                self.completion?(.fileUploaded(nextToUpload))
                
            case .serverMasterVersionUpdate(let masterVersionUpdate):
                // Simplest method for now: Mark all uft's as .notStarted
                // TODO: *4* This could be better-- performance-wise, it doesn't make sense to do all the uploads over again.
                uploadQueue.uploadFileTrackers.map { uft in
                    uft.status = .notStarted
                }

                Singleton.get().masterVersion = masterVersionUpdate
                CoreData.sessionNamed(Constants.coreDataName).saveContext()
                self.completion?(.masterVersionUpdate)
            }
        }
    }
    
    enum DoneUploadsCompletion {
    case doneUploads(numberTransferred: Int64)
    case masterVersionUpdate
    case error(String)
    }
    
    func doneUploads(completion:((DoneUploadsCompletion)->())?) {
        let masterVersion = Singleton.get().masterVersion
        ServerAPI.session.doneUploads(serverMasterVersion: masterVersion) { (result, error) in
            guard error == nil else {
                completion?(.error("\(error)"))
                return
            }
            
            switch result! {
            case .success(numberUploadsTransferred: let numberTransferred):
                // Master version was incremented on the server as part of normal doneUploads operation. Update ours locally.
                Singleton.get().masterVersion = masterVersion + 1
                CoreData.sessionNamed(Constants.coreDataName).saveContext()
                
                completion?(.doneUploads(numberTransferred: numberTransferred))
                
            case .serverMasterVersionUpdate(let masterVersionUpdate):
                guard let uploadQueue = Upload.getHeadSyncQueue() else {
                    completion?(.error("Failed on getHeadSyncQueue"))
                    return
                }
                
                // Simplest method for now: Mark all uft's as .notStarted
                // TODO: *4* This could be better-- performance-wise, it doesn't make sense to do all the uploads over again.
                uploadQueue.uploadFileTrackers.map { uft in
                    uft.status = .notStarted
                }

                Singleton.get().masterVersion = masterVersionUpdate
                CoreData.sessionNamed(Constants.coreDataName).saveContext()
                completion?(.masterVersionUpdate)
            }
        }
    }
}
