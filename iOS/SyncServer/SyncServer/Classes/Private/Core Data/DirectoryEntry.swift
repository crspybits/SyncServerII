//
//  DirectoryEntry.swift
//  Pods
//
//  Created by Christopher Prince on 2/24/17.
//
//

import Foundation
import CoreData
import SMCoreLib

@objc(DirectoryEntry)
public class DirectoryEntry: NSManagedObject, CoreDataModel, AllOperations {
    typealias COREDATAOBJECT = DirectoryEntry

    public static let UUID_KEY = "fileUUID"
    
    public class func entityName() -> String {
        return "DirectoryEntry"
    }
    
    public class func newObject() -> NSManagedObject {
        let directoryEntry = CoreData.sessionNamed(Constants.coreDataName).newObject(withEntityName: self.entityName()) as! DirectoryEntry
        directoryEntry.deletedOnServer = false
        return directoryEntry
    }
    
    class func fetchObjectWithUUID(uuid:String) -> DirectoryEntry? {
        let managedObject = CoreData.fetchObjectWithUUID(uuid, usingUUIDKey: UUID_KEY, fromEntityName: self.entityName(), coreDataSession: CoreData.sessionNamed(Constants.coreDataName))
        return managedObject as? DirectoryEntry
    }
}
