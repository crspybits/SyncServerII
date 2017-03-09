//
//  DownloadFileTracker+CoreDataProperties.swift
//  Pods
//
//  Created by Christopher Prince on 3/2/17.
//
//

import Foundation
import CoreData


extension DownloadFileTracker {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<DownloadFileTracker> {
        return NSFetchRequest<DownloadFileTracker>(entityName: "DownloadFileTracker");
    }

    @NSManaged public var deletedOnServer: Bool

}
