//
//  Directory.swift
//  SyncServer
//
//  Created by Christopher Prince on 2/23/17.
//
//

import Foundation
import SMCoreLib

// Meta info for files known to the client.

class Directory {
    static var session = Directory()
    
    private init() {
    }
    
    // Compares the passed fileIndex to the current DirecotoryEntry objects, and returns just the FileInfo objects we need to download, if any.
    func checkFileIndex(fileIndex:[FileInfo]) -> (downloadFiles:[FileInfo]?, downloadDeletions:[FileInfo]?)  {
    
        var downloadFiles = [FileInfo]()
        // var downloadDeletions = [FileInfo]()

        for file in fileIndex {
            var needToDownload = false
            
            if let entry = DirectoryEntry.fetchObjectWithUUID(uuid: file.fileUUID) {
                // Have the file in client directory.
                
                if entry.fileVersion != file.fileVersion {
                    // Not same version here locally as on server:
                    needToDownload = true
                }
                // Else: No need to download.
            }
            else {
                // File unknown to the client: Need to create DirectoryEntry.
                let entry = DirectoryEntry.newObject() as! DirectoryEntry
                entry.fileUUID = file.fileUUID
                entry.fileVersion = file.fileVersion

                needToDownload = true
            }
            
            // if file.deleted! {
            // }
            
            if needToDownload {
                downloadFiles += [file]
            }
        }

        return (downloadFiles, nil)
    }
}
