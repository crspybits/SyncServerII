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
    
    // If a user revokes their access token, or it expires, I want to make sure we provide gracefully degraded service.
    case accessTokenRevokedOrExpired
    
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

public enum DownloadResult {
    // Checksum: value defined by the cloud storage system. This is the checksum value *before* the download.
    case success (data: Data, checkSum: String)
    
    // This is distinguished from the more general failure case because (a) it definitively relects the file not being present in cloud storage, and (b) because it could be due to the user either renaming the file in cloud storage or the file being deleted by the user.
    case fileNotFound
    
    // Similarly, if a user revokes their access token, I want to make sure we provide gracefully degraded service.
    case accessTokenRevokedOrExpired
    
    case failure(Swift.Error)
}

protocol CloudStorage {
    // On success, String in result gives checksum of file on server.
    // Returns .failure(CloudStorageError.alreadyUploaded) in completion if the named file already exists.
    func uploadFile(cloudFileName:String, data:Data, options:CloudStorageFileNameOptions?,
        completion:@escaping (Result<String>)->())
    
    func downloadFile(cloudFileName:String, options:CloudStorageFileNameOptions?, completion:@escaping (DownloadResult)->())
    
    func deleteFile(cloudFileName:String, options:CloudStorageFileNameOptions?,
        completion:@escaping (Result<()>)->())

    // On success, returns true iff the file was found.
    // Used primarily for testing.
    func lookupFile(cloudFileName:String, options:CloudStorageFileNameOptions?,
        completion:@escaping (Result<Bool>)->())
}
