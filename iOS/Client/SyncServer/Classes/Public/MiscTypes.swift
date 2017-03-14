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

// Attributes for a data object being synced.
public struct SyncAttributes {
    public var fileUUID:String!
    public var mimeType:String!
    
    // Internally, we use file versions. However, client's don't need to know about those-- clients just upload files and receive downloads.
    // public var fileVersion:FileVersionInt!
    
    public var appMetaData:String?
    
    public init(fileUUID:String, mimeType:String) {
        self.fileUUID = fileUUID
        self.mimeType = mimeType
    }
}

