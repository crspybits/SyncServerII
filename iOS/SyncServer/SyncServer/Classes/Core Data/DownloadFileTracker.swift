//
//  DownloadFileTracker.swift
//  Pods
//
//  Created by Christopher Prince on 2/24/17.
//
//

import Foundation
import CoreData
import SMCoreLib

@objc(DownloadFileTracker)
public class DownloadFileTracker: NSManagedObject {
    public class func entityName() -> String {
        return "DownloadFileTracker"
    }
    
    public class func newObject() -> NSManagedObject {
        let dft = CoreData.sessionNamed(Constants.coreDataName).newObject(withEntityName: self.entityName())
        return dft!
    }
    
    public class func removeAll() {
        do {
            let dfts = try CoreData.sessionNamed(Constants.coreDataName).fetchAllObjects(withEntityName: self.entityName()) as? [DownloadFileTracker]
            
            for dft in dfts! {
                CoreData.sessionNamed(Constants.coreDataName).remove(dft)
            }
            
            CoreData.sessionNamed(Constants.coreDataName).saveContext()
        } catch (let error) {
            Log.error("Error: \(error)")
            assert(false)
        }
    }
}
