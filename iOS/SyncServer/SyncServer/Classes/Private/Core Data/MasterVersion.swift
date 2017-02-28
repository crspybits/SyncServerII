//
//  MasterVersion+CoreDataClass.swift
//  Pods
//
//  Created by Christopher Prince on 2/24/17.
//
//

import Foundation
import CoreData
import SMCoreLib

@objc(MasterVersion)
class MasterVersion: NSManagedObject {
    public class func entityName() -> String {
        return "MasterVersion"
    }
    
    class func newObject() -> NSManagedObject {
        let masterVersion = CoreData.sessionNamed(Constants.coreDataName).newObject(withEntityName: self.entityName()) as! MasterVersion
        masterVersion.version = 0
        return masterVersion
    }
    
    // Get the singleton.
    class func get() -> MasterVersion {
        var mvs = [MasterVersion]()
        var mv:MasterVersion?
        
        do {
            let objs = try CoreData.sessionNamed(Constants.coreDataName).fetchAllObjects(withEntityName: MasterVersion.entityName())
            mvs = objs as! [MasterVersion]
        } catch (let error) {
            assert(false)
        }
        
        if mvs.count == 0 {
            mv = MasterVersion.newObject() as! MasterVersion
            mv!.version = 0
        }
        else if mvs.count > 1 {
            assert(false)
        }
        else {
            mv = mvs[0]
        }
        
        return mv!
    }
}
