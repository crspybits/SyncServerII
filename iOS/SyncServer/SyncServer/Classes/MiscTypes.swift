//
//  MiscTypes.swift
//  Pods
//
//  Created by Christopher Prince on 2/23/17.
//
//

import Foundation

public typealias AppMetaData = [String:AnyObject]

// Attributes for a data object being synced.
public class SyncAttributes {
    public var fileUUID:String!
    public var fileVersion:FileVersionInt!
    
    public init(fileUUID:String, fileVersion: FileVersionInt) {
        self.fileUUID = fileUUID
        self.fileVersion = fileVersion
    }
}
