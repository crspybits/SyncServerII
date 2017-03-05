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
    
    private init() {
    }
    
    enum NextResult {
    case started
    case noUploads
    case allUploadsCompleted
    case error(String)
    }
    
    enum NextCompletion {
    case uploaded(UploadFileTracker)
    case masterVersionUpdate
    case error(String)
    }
    
    // Starts upload of next file, if there is one. There should be no files uploading already. Only if .started is the NextResult will the completion handler be called. With a masterVersionUpdate response for NextCompletion, the MasterVersion Core Data object is updated by this method, and all the UploadFileTracker objects have been reset.
    func next(completion:((NextCompletion)->())?) -> NextResult {
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

        let file = ServerAPI.File(localURL: nextToUpload.localURL! as URL!, fileUUID: nextToUpload.fileUUID, mimeType: nextToUpload.mimeType, cloudFolderName: cloudFolderName, deviceUUID:deviceUUID, appMetaData: nextToUpload.appMetaData, fileVersion: nextToUpload.fileVersion)

        nextToUpload.status = .uploading
        CoreData.sessionNamed(Constants.coreDataName).saveContext()
        
        ServerAPI.session.uploadFile(file: file, serverMasterVersion: masterVersion) { (uploadResult, error) in
            guard error == nil else {
                nextToUpload.status = .notStarted
                CoreData.sessionNamed(Constants.coreDataName).saveContext()
                
                let message = "Error: \(error)"
                Log.error(message)
                completion?(.error(message))
                return
            }
 
            switch uploadResult! {
            case .success(sizeInBytes: let sizeInBytes):
                nextToUpload.status = .uploaded
                CoreData.sessionNamed(Constants.coreDataName).saveContext()
                completion?(.uploaded(nextToUpload))
                
            case .serverMasterVersionUpdate(let masterVersionUpdate):
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
        
        return .started
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
