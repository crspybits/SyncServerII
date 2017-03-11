//
//  Image+CoreDataClass.swift
//  SharedImages
//
//  Created by Christopher Prince on 3/10/17.
//  Copyright © 2017 Spastic Muffin, LLC. All rights reserved.
//

import Foundation
import CoreData
import SMCoreLib

@objc(Image)
public class Image: NSManagedObject {
    static let CREATION_DATE_KEY = "creationDate"
    
    var url:SMRelativeLocalURL? {
        get {
            if urlInternal == nil {
                return nil
            }
            else {
                let url = NSKeyedUnarchiver.unarchiveObject(with: urlInternal as! Data) as? SMRelativeLocalURL
                Assert.If(url == nil, thenPrintThisString: "Yikes: No URL!")
                return url
            }
        }
        
        set {
            if newValue == nil {
                urlInternal = nil
            }
            else {
                urlInternal = NSKeyedArchiver.archivedData(withRootObject: newValue!) as NSData?
            }
        }
    }
    
    
    class func entityName() -> String {
        return "Image"
    }

    // Only may throw when makeUUIDAndUpload is true.
    class func newObjectAndMakeUUID(makeUUID: Bool) -> NSManagedObject {
        let image = CoreData.sessionNamed(CoreDataExtras.sessionName).newObject(withEntityName: self.entityName()) as! Image
        
        if makeUUID {
            image.uuid = UUID.make()
        }
        
        image.creationDate = NSDate()
        
        return image
    }
    
    class func newObject() -> NSManagedObject {
        return newObjectAndMakeUUID(makeUUID: false)
    }
    
    class func fetchRequestForAllObjects() -> NSFetchRequest<NSFetchRequestResult>? {
        var fetchRequest: NSFetchRequest<NSFetchRequestResult>?
        fetchRequest = CoreData.sessionNamed(CoreDataExtras.sessionName).fetchRequest(withEntityName: self.entityName(), modifyingFetchRequestWith: nil)
        
        if fetchRequest != nil {
            let sortDescriptor = NSSortDescriptor(key: CREATION_DATE_KEY, ascending: false)
            fetchRequest!.sortDescriptors = [sortDescriptor]
        }
        
        return fetchRequest
    }
}
