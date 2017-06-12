//
//  MiscTypes.swift
//  Pods
//
//  Created by Christopher Prince on 2/23/17.
//
//

import Foundation
import SMCoreLib

public typealias AppMetaData = [String:AnyObject]
public typealias UUIDString = String

// Attributes for a data object being synced.
public struct SyncAttributes {
    public var fileUUID:String!
    public var mimeType:String!
    public var appMetaData:String?
    
    // These are only present during download delegate calls
    public var creationDate:Date?
    public var updateDate:Date?
    
    public init(fileUUID:String, mimeType:String) {
        self.fileUUID = fileUUID
        self.mimeType = mimeType
    }
}



