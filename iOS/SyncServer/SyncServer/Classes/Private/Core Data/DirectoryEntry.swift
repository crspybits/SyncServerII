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
public class DirectoryEntry: NSManagedObject, CoreDataModel {
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
    
    public class func fetchAll() -> [DirectoryEntry] {
        var entries:[DirectoryEntry]!

        do {
            entries = try CoreData.sessionNamed(Constants.coreDataName).fetchAllObjects(withEntityName: self.entityName()) as? [DirectoryEntry]
         } catch (let error) {
            Log.error("Error: \(error)")
            assert(false)
         }
        
         return entries
    }
    
    public class func removeAll() {
        do {
            let entries = try CoreData.sessionNamed(Constants.coreDataName).fetchAllObjects(withEntityName: self.entityName()) as? [DirectoryEntry]
            
            for entry in entries! {
                CoreData.sessionNamed(Constants.coreDataName).remove(entry)
            }            
        } catch (let error) {
            Log.error("Error: \(error)")
            assert(false)
        }
    }
}
