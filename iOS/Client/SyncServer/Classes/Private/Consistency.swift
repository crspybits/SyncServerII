//
//  Consistency.swift
//  SyncServer
//
//  Created by Christopher Prince on 3/14/17.
//
//

import Foundation
import SMCoreLib

class Consistency {
    static func check(localFiles:[UUIDString], repair:Bool = false, callback:((Error?)->())?) {
        ServerAPI.session.fileIndex { (fileInfo, masterVersion, error) in
            guard error == nil else {
                callback?(error)
                return
            }
            
            var messageResult = ""

            // Present in local meta data, but not present locally. (If the file was not present in local meta data and not present locally, a sync would have fixed this).
            var serverFilesNotPresentLocally = [UUIDString]()
            
            // Present in local meta data, but not deleted.
            var deletedServerFilesButPresentLocally = [UUIDString]()

            // First, check server files.
            for file in fileInfo! {
                // Check against local files.
                if file.deleted! {
                    if localFiles.contains(file.fileUUID) {
                        messageResult += "Deleted Server file: \(file.fileUUID!) *is* in local files\n"
                    }
                }
                else {
                    if !localFiles.contains(file.fileUUID!) {
                        serverFilesNotPresentLocally += [file.fileUUID!]
                        messageResult += "Server file: \(file.fileUUID!) not in local files \(localFiles)\n"
                    }
                }
                
                // We should have *every* entry in the local DirectoryEntry meta data also. These issues should never happen: Our sync should prevent these.
                let entry = DirectoryEntry.fetchObjectWithUUID(uuid: file.fileUUID)
                if entry == nil {
                    messageResult += "Server file: \(file.fileUUID!) not in DirectoryEntry meta data\n"
                }
                else if entry!.deletedOnServer != file.deleted {
                    messageResult += "Server file: \(file.fileUUID!) and DirectoryEntry meta data have inconsistent deletion status: \(file.deleted!) versus \(entry!.deletedOnServer)\n"
                }
            }
            
            for localFile in localFiles {
                // All local files should be non-deleted on server
                let result = fileInfo!.filter {$0.fileUUID == localFile}
                if result.count == 0 {
                    messageResult += "Local file: \(localFile) not on server\n"
                }
                else if result[0].deleted! {
                    messageResult += "Local file: \(localFile) deleted on server\n"
                }
                
                // And those local files should *all* be in the local meta data.
                let entry = DirectoryEntry.fetchObjectWithUUID(uuid: localFile)
                if entry == nil {
                    messageResult += "Local file: \(localFile) not in DirectoryEntry meta data\n"
                }
                else if entry!.deletedOnServer {
                    messageResult += "Local file: \(localFile) marked as deleted in DirectoryEntry meta data\n"
                }
            }
            
            // All the local data should be on the server.
            let entries = DirectoryEntry.fetchAll()
            if entries.count != fileInfo!.count {
                messageResult += "DirectoryEntry meta data different size than on server: \(entries.count) versus \(fileInfo!.count)\n"
            }
            
            if messageResult.characters.count > 0 {
                messageResult = "\nConsistency check: Results through \(localFiles.count) local files, \(fileInfo!.count) server files, and \(entries.count) DirectoryEntry meta data entries:\n\(messageResult)"
                Log.warning(messageResult)
            }
            else {
                messageResult = "Consistency check: OK!"
                Log.special(messageResult)
            }
            
            if repair {
                repairServerFilesNotPresentLocally(fileUUIDs: serverFilesNotPresentLocally) {
                    callback?(nil)
                }
            }
            else {
                callback?(nil)
            }
        }
    }
    
    static func repairServerFilesNotPresentLocally(fileUUIDs:[UUIDString], completion:@escaping ()->()) {
        if fileUUIDs.count == 0 {
            completion()
        }
        
        // The simplest means to deal with this seems to be to remove the associated DirectoryEntry, and then sync again.
        for fileUUID in fileUUIDs {
            let entry = DirectoryEntry.fetchObjectWithUUID(uuid: fileUUID)
            CoreData.sessionNamed(Constants.coreDataName).remove(entry!)
        }
        
        CoreData.sessionNamed(Constants.coreDataName).saveContext()
        
        // A bit odd calling back up to the SyncServer, but sync will not call back down to us.
        SyncServer.session.sync() {
            completion()
        }
    }
}
