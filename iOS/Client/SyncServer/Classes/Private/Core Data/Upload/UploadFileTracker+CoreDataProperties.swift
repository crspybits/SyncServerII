//
//  UploadFileTracker+CoreDataProperties.swift
//  Pods
//
//  Created by Christopher Prince on 3/2/17.
//
//

import Foundation
import CoreData


extension UploadFileTracker {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<UploadFileTracker> {
        return NSFetchRequest<UploadFileTracker>(entityName: "UploadFileTracker");
    }

    @NSManaged public var deleteOnServer: Bool
    @NSManaged public var queue: UploadQueue?

}
