//
//  DirectoryEntry+CoreDataProperties.swift
//  Pods
//
//  Created by Christopher Prince on 3/3/17.
//
//

import Foundation
import CoreData


extension DirectoryEntry {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<DirectoryEntry> {
        return NSFetchRequest<DirectoryEntry>(entityName: "DirectoryEntry");
    }

    @NSManaged public var deletedOnServer: Bool
    @NSManaged public var fileUUID: String?
    @NSManaged public var fileVersion: Int32
    @NSManaged public var mimeType: String?

}
