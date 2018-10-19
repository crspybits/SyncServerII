//
//  CloudStorage.swift
//  Server
//
//  Created by Christopher G Prince on 12/3/17.
//

import Foundation
import SyncServerShared

enum Result<T> {
    case success(T)
    case failure(Swift.Error)
}

// Some cloud services (e.g., Google Drive) need additional file naming options; other's don't (e.g., Dropbox). If you give these options and the method doesn't need it, they are ignored.
struct CloudStorageFileNameOptions {
    // `String?` because only some cloud storage services need it.
    let cloudFolderName:String?
    
    let mimeType:String
}

public enum CloudStorageError : Int, Swift.Error {
    case alreadyUploaded
}

public struct DownloadResult {
    let data: Data
    
    // A checksum value defined by the cloud storage system. This is the checksum value *before* the download.
    let checkSum: String
}

protocol CloudStorage {
    // On success, Int in result gives file size in bytes on server.
    // Returns .failure(CloudStorageError.alreadyUploaded) in completion if the named file already exists.
    func uploadFile(cloudFileName:String, data:Data, options:CloudStorageFileNameOptions?,
        completion:@escaping (Result<Int>)->())
    
    func downloadFile(cloudFileName:String, options:CloudStorageFileNameOptions?, completion:@escaping (Result<DownloadResult>)->())
    
    func deleteFile(cloudFileName:String, options:CloudStorageFileNameOptions?,
        completion:@escaping (Swift.Error?)->())

    // On success, returns true iff the file was found.
    // Used primarily for testing.
    func lookupFile(cloudFileName:String, options:CloudStorageFileNameOptions?,
        completion:@escaping (Result<Bool>)->())
}
