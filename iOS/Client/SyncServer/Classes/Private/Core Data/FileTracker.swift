//
//  FileTracker+CoreDataClass.swift
//  Pods
//
//  Created by Christopher Prince on 3/2/17.
//
//

import Foundation
import CoreData
import SMCoreLib

@objc(FileTracker)
public class FileTracker: NSManagedObject, Filenaming {
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
    
    var localURL:SMRelativeLocalURL? {
        get {
            if localURLData == nil {
                return nil
            }
            else {
                let url = NSKeyedUnarchiver.unarchiveObject(with: localURLData! as Data) as? SMRelativeLocalURL
                Assert.If(url == nil, thenPrintThisString: "Yikes: No URL!")
                return url
            }
        }
        
        set {
            if newValue == nil {
                localURLData = nil
            }
            else {
                localURLData = NSKeyedArchiver.archivedData(withRootObject: newValue!) as NSData
            }
        }
    }
}
