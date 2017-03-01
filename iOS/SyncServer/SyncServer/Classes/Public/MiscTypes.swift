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
    public var fileVersion:FileVersionInt!
}

// This information is for testing purposes and for UI (e.g., for displaying download progress).
public enum SyncEvent {
    // The url/attr here may not be consistent with the results from shouldSaveDownloads in the SyncServerDelegate.
    case singleDownloadComplete(url:SMRelativeLocalURL, attr: SyncAttributes)
}
