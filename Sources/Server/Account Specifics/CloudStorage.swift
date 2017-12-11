//
//  CloudStorage.swift
//  Server
//
//  Created by Christopher G Prince on 12/3/17.
//

import Foundation
import SyncServerShared

protocol CloudStorage {
    func uploadFile(deviceUUID:String, request:UploadFileRequest,
        completion:@escaping (_ fileSizeOnServerInBytes:Int?, Swift.Error?)->())
    func downloadFile(cloudFolderName:String, cloudFileName:String, mimeType:String,
        completion:@escaping (_ fileData:Data?, Swift.Error?)->())
    func deleteFile(cloudFolderName:String, cloudFileName:String, mimeType:String,
        completion:@escaping (Swift.Error?)->())
}
