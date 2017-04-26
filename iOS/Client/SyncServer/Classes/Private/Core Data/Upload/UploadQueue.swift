//
//  UploadQueue.swift
//  SyncServer
//
//  Created by Christopher Prince on 3/2/17.
//
//  This file was automatically generated and should not be edited.
//

import Foundation
import CoreData
import SMCoreLib

@objc(UploadQueue)
public class UploadQueue: NSManagedObject, AllOperations {
    typealias COREDATAOBJECT = UploadQueue

    public class func entityName() -> String {
        return "UploadQueue"
    }
    
    public class func newObject() -> NSManagedObject {
        let uploadQueue = CoreData.sessionNamed(Constants.coreDataName).newObject(withEntityName: self.entityName()) as! UploadQueue
        return uploadQueue
    }
    
    func nextUpload() -> UploadFileTracker? {
        let result = uploads!.filter {
            let uft = $0 as! UploadFileTracker
            return uft.status == .notStarted
        }
        
        guard result.count > 0 else {
            return nil
        }
        
        return (result[0] as! UploadFileTracker)
    }
    
    var uploadFileTrackers:[UploadFileTracker] {
        return uploads!.array as! [UploadFileTracker]
    }
}
