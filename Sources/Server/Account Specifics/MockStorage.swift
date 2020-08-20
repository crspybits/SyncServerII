//
//  MockStorage.swift
//  ServerPackageDescription
//
//  Created by Christopher G Prince on 6/27/19.
//

import Foundation
import ServerAccount
import ServerShared
import LoggerAPI

// Stubs of the CloudStorage protocol for load testing so that I don't run into limits with particular cloud storage systems under higher loads.
// Going to consider this a "Google" type for purposes of generating hashes.

class MockStorage: CloudStorage {
    enum Errors: Swift.Error {
        case fileNotFound
        case uploadSetupFailed
        case downloadSetupFailed
    }
    
    let lowDurationMillseconds: Int = 1
    let highDurationMilliseconds: Int = 20
    
    // Mapping from cloud file name to contents. I'm making this static to make testing easier.
    private static var directory = [String: Data]()
    
    private var duration: Int {
        return Int.random(in: lowDurationMillseconds...highDurationMilliseconds)
    }
    
    static func reset() {
        Log.info("MockStorage: reset")
        directory.removeAll()
    }
    
    private func runAfterDuration(completion: @escaping ()->()) {
        DispatchQueue.global().asyncAfter(deadline: .now() + .milliseconds(duration)) {
            completion()
        }
    }
    
    private func getHash(data: Data) -> String? {
        guard let hash = Hashing.hashOf(data: data, for: .Google) else {
            Log.error("Failed getting hash: Hash")
            return nil
        }
        
        return hash
    }

    func uploadFile(cloudFileName: String, data: Data, options: CloudStorageFileNameOptions?, completion: @escaping (Result<String>) -> ()) {
        Log.debug("MockStorage: uploadFile: \(cloudFileName)")
        
        Self.directory[cloudFileName] = data
        
        guard let hash = getHash(data: data) else {
            completion(.failure(Errors.uploadSetupFailed))
            return
        }

        runAfterDuration {
            completion(.success(hash))
        }
    }
    
    func downloadFile(cloudFileName: String, options: CloudStorageFileNameOptions?, completion: @escaping (DownloadResult) -> ()) {
        Log.debug("MockStorage: downloadFile: \(cloudFileName)")

        runAfterDuration {
            guard let data = Self.directory[cloudFileName] else {
                completion(.fileNotFound)
                return
            }

            guard let hash = self.getHash(data: data) else {
                completion(.failure(Errors.downloadSetupFailed))
                return
            }
            
            completion(.success(data: data, checkSum: hash))
        }
    }
    
    func deleteFile(cloudFileName: String, options: CloudStorageFileNameOptions?, completion: @escaping (Result<()>) -> ()) {
        Log.debug("MockStorage: deleteFile: \(cloudFileName)")

        guard let _ = Self.directory[cloudFileName] else {
            completion(.failure(Errors.fileNotFound))
            return
        }
        
        Self.directory.removeValue(forKey: cloudFileName)
            
        runAfterDuration {
            completion(.success(()))
        }
    }
    
    func lookupFile(cloudFileName: String, options: CloudStorageFileNameOptions?, completion: @escaping (Result<Bool>) -> ()) {
        Log.debug("MockStorage: lookupFile: \(cloudFileName)")

        guard let _ = Self.directory[cloudFileName] else {
            completion(.success(false))
            return
        }
        
        runAfterDuration {
            completion(.success(true))
        }
    }
}
