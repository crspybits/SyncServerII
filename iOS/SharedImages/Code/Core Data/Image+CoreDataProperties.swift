//
//  Image+CoreDataProperties.swift
//  SharedImages
//
//  Created by Christopher Prince on 3/10/17.
//  Copyright © 2017 Spastic Muffin, LLC. All rights reserved.
//

import Foundation
import CoreData


extension Image {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<Image> {
        return NSFetchRequest<Image>(entityName: "Image");
    }

    @NSManaged public var uuid: String?
    @NSManaged public var urlInternal: NSData?
    @NSManaged public var creationDate: NSDate?

}
