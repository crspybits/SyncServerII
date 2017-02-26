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
class DownloadFileTracker: NSManagedObject, Filenaming {
    var fileUUID:String! {
        get {
            return fileUUIDInternal!
        }
        
        set {
            fileUUIDInternal = newValue
        }
    }
    
    var fileVersion:Int32! {
        get {
            return fileVersionInternal
        }
        
        set {
            fileVersionInternal = newValue
        }
    }
    
    enum Status : String {
    case notStarted
    case downloading
    case downloaded
    }
    
    var status:Status {
        get {
            return Status(rawValue: statusRaw!)!
        }
        
        set {
            statusRaw = newValue.rawValue
        }
    }
    
    var localURL:SMRelativeLocalURL? {
        get {
            if localURLData == nil {
                return nil
            }
            else {
                let url = NSKeyedUnarchiver.unarchiveObject(with: localURLData as! Data) as? SMRelativeLocalURL
                Assert.If(url == nil, thenPrintThisString: "Yikes: No URL!")
                return url
            }
        }
        
        set {
            if newValue == nil {
                localURLData = nil
            }
            else {
                localURLData = NSKeyedArchiver.archivedData(withRootObject: newValue!) as! NSData
            }
        }
    }
    
    class func entityName() -> String {
        return "DownloadFileTracker"
    }
    
    class func newObject() -> NSManagedObject {
        let dft = CoreData.sessionNamed(Constants.coreDataName).newObject(withEntityName: self.entityName()) as! DownloadFileTracker
        dft.status = .notStarted
        return dft
    }
    
    class func fetchAll() -> [DownloadFileTracker] {
        var dfts:[DownloadFileTracker]!

        do {
            dfts = try CoreData.sessionNamed(Constants.coreDataName).fetchAllObjects(withEntityName: self.entityName()) as? [DownloadFileTracker]
         } catch (let error) {
            Log.error("Error: \(error)")
            assert(false)
         }
        
         return dfts
    }
    
    func reset() {
        status = .notStarted
        appMetaData = nil
        localURL = nil
        fileSizeBytes = 0
    }
    
    class func removeAll() {
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
