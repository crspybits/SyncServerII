//
//  Uploads.swift
//  SyncServer
//
//  Created by Christopher Prince on 3/2/17.
//
//

import Foundation
import SMCoreLib

extension Upload {
    private class func createNewPendingSync() {
        Singleton.get().pendingSync = UploadQueue.newObject() as! UploadQueue
        CoreData.sessionNamed(Constants.coreDataName).saveContext()
    }
    
    class func pendingSync() -> UploadQueue {
        if Singleton.get().pendingSync == nil {
            createNewPendingSync()
        }
        
        return Singleton.get().pendingSync!
    }
    
    // Must have uploads in `pendingSync`
    class func movePendingSyncToSynced() {
        assert(Singleton.get().pendingSync != nil)
        assert(Singleton.get().pendingSync!.uploads!.count > 0)
        
        let uploadQueues = synced()
        uploadQueues.addToQueues(Singleton.get().pendingSync!)
        
        // This does a `saveContext`, so don't need to do that again.
        createNewPendingSync()        
    }
    
    class func synced() -> UploadQueues {
        return UploadQueues.get()
    }
    
    class func haveSyncQueue() -> Bool {
        return synced().queues!.count > 0
    }
    
    class func getHeadSyncQueue() -> UploadQueue? {
        if !haveSyncQueue()  {
            return nil
        }
        
        return synced().queues![0] as! UploadQueue
    }
    
    // There must be a head sync queue.
    class func removeHeadSyncQueue() {
        let head = getHeadSyncQueue()
        assert(head != nil)
        CoreData.sessionNamed(Constants.coreDataName).remove(head!)
    }
}
