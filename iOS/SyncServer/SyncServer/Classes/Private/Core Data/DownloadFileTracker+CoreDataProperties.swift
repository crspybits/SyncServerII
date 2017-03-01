//
//  DownloadFileTracker+CoreDataProperties.swift
//  Pods
//
//  Created by Christopher Prince on 2/27/17.
//
//

import Foundation
import CoreData


extension DownloadFileTracker {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<DownloadFileTracker> {
        return NSFetchRequest<DownloadFileTracker>(entityName: "DownloadFileTracker");
    }

    @NSManaged public var fileUUIDInternal: String?
    @NSManaged public var fileVersionInternal: Int32
    @NSManaged public var statusRaw: String?
    @NSManaged public var localURLData: NSData?
    @NSManaged public var fileSizeBytes: Int64
    @NSManaged public var appMetaData: String?
    @NSManaged public var deletedOnServer: Bool

}
