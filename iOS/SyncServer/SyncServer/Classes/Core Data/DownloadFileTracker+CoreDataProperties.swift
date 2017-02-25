//
//  DownloadFileTracker+CoreDataProperties.swift
//  Pods
//
//  Created by Christopher Prince on 2/24/17.
//
//  This file was automatically generated and should not be edited.
//

import Foundation
import CoreData


extension DownloadFileTracker {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<DownloadFileTracker> {
        return NSFetchRequest<DownloadFileTracker>(entityName: "DownloadFileTracker");
    }

    @NSManaged public var fileUUID: String?
    @NSManaged public var fileVersion: Int32

}
