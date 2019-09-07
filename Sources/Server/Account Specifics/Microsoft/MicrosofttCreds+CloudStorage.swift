//
//  MicrosofttCreds+CloudStorage.swift
//  Server
//
//  Created by Christopher G Prince on 9/7/19.
//

import Foundation

extension MicrosoftCreds : CloudStorage {
    func uploadFile(cloudFileName: String, data: Data, options: CloudStorageFileNameOptions?, completion: @escaping (Result<String>) -> ()) {
    }
    
    func downloadFile(cloudFileName: String, options: CloudStorageFileNameOptions?, completion: @escaping (DownloadResult) -> ()) {
    }
    
    func deleteFile(cloudFileName: String, options: CloudStorageFileNameOptions?, completion: @escaping (Result<()>) -> ()) {
    }
    
    func lookupFile(cloudFileName: String, options: CloudStorageFileNameOptions?, completion: @escaping (Result<Bool>) -> ()) {
    }
}

