//
//  Filenaming.swift
//  Server
//
//  Created by Christopher Prince on 1/20/17.
//
//

import Foundation

// In some situations on the client, I need this
#if !SERVER
struct FilenamingObject : Filenaming {
    let fileUUID:String!
    let fileVersion:Int32!
}
#endif

protocol Filenaming {
    var fileUUID:String! {get}
    var fileVersion:Int32! {get}

#if SERVER
    func cloudFileName(deviceUUID:String) -> String
#endif
}

#if SERVER
extension Filenaming {
    
    /* We are not going to use just the file UUID to name the file in the cloud service. This is because we are not going to hold a lock across multiple file uploads, and we need to make sure that we don't have a conflict when two or more devices attempt to concurrently upload the same file. The file name structure we're going to use is given by this method.
    */
    func cloudFileName(deviceUUID:String) -> String {
        return "\(fileUUID!).\(deviceUUID).\(fileVersion!)"
    }
}
#endif
