//
//  FileTracker+CoreDataProperties.swift
//  Pods
//
//  Created by Christopher Prince on 6/9/17.
//
//

import Foundation
import CoreData


extension FileTracker {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<FileTracker> {
        return NSFetchRequest<FileTracker>(entityName: "FileTracker")
    }

    @NSManaged public var appMetaData: String?
    @NSManaged public var fileSizeBytes: Int64
    @NSManaged public var fileUUIDInternal: String?
    @NSManaged public var fileVersionInternal: Int32
    @NSManaged public var localURLData: NSData?
    @NSManaged public var mimeType: String?
    @NSManaged public var statusRaw: String?
    @NSManaged public var creationDate: NSDate?
    @NSManaged public var updateDate: NSDate?

}
