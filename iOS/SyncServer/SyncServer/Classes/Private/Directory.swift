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
    
    // Compares the passed fileIndex to the current DirecotoryEntry objects, and returns just the FileInfo objects we need to download, if any. The directory is not changed as a result of this call.
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
                // File unknown to the client: Need to create DirectoryEntry-- later.
                // Not going to create directory entry now because then this state looks identical to having downloaded the file/version previously.
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
    
    func updateAfterDownloadingFiles(dfts:[DownloadFileTracker]) {
        dfts.map { dft in
            if let entry = DirectoryEntry.fetchObjectWithUUID(uuid: dft.fileUUID) {
                assert(entry.fileVersion < dft.fileVersion)
                entry.fileVersion = dft.fileVersion
            }
            else {
                let newEntry = DirectoryEntry.newObject() as! DirectoryEntry
                newEntry.fileUUID = dft.fileUUID
                newEntry.fileVersion = dft.fileVersion
            }
        }
    }
}
