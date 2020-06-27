//
//  MockStorage.swift
//  ServerPackageDescription
//
//  Created by Christopher G Prince on 6/27/19.
//

import Foundation
import ServerAccount

// Stubs of the CloudStorage protocol for load testing so that I don't run into limits with particular cloud storage systems under higher loads.

class MockStorage: CloudStorage {
    let lowDuration: Int = 1
    let highDuration: Int = 20
    
    private var duration: Int {
        return Int.random(in: lowDuration...highDuration)
    }
    
    private func runAfterDuration(completion: @escaping ()->()) {
        DispatchQueue.global().asyncAfter(deadline: .now() + .seconds(duration)) {
            completion()
        }
    }

    func uploadFile(cloudFileName: String, data: Data, options: CloudStorageFileNameOptions?, completion: @escaping (Result<String>) -> ()) {
        runAfterDuration {
            completion(.success("not-really-a-hash"))
        }
    }
    
    func downloadFile(cloudFileName: String, options: CloudStorageFileNameOptions?, completion: @escaping (DownloadResult) -> ()) {
        runAfterDuration {
            let data = "foobar".data(using: .utf8)!
            completion(.success(data: data, checkSum: "not-really-a-hash"))
        }
    }
    
    func deleteFile(cloudFileName: String, options: CloudStorageFileNameOptions?, completion: @escaping (Result<()>) -> ()) {
        runAfterDuration {
            completion(.success(()))
        }
    }
    
    func lookupFile(cloudFileName: String, options: CloudStorageFileNameOptions?, completion: @escaping (Result<Bool>) -> ()) {
        runAfterDuration {
            completion(.success(true))
        }
    }
}
