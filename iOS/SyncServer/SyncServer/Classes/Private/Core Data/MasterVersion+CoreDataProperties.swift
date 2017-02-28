//
//  MasterVersion+CoreDataProperties.swift
//  Pods
//
//  Created by Christopher Prince on 2/24/17.
//
//  This file was automatically generated and should not be edited.
//

import Foundation
import CoreData


extension MasterVersion {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<MasterVersion> {
        return NSFetchRequest<MasterVersion>(entityName: "MasterVersion");
    }

    @NSManaged public var version: Int64

}
