//
//  Hashing.swift
//  SyncServer
//
//  Created by Christopher G Prince on 10/21/18.
//

// For mock storage

import Foundation
import ServerShared
import CryptoSwift
import LoggerAPI

class Hashing {
    private static let dropboxBlockSize = 1024 * 1024 * 4
    
    static func generateDropbox(fromData data: Data) -> String? {
        var concatenatedSHAs = Data()
        
        var remainingLength = data.count
        if remainingLength == 0 {
            return nil
        }
        
        var startIndex = data.startIndex

        while true {
            let nextBlockSize = min(remainingLength, dropboxBlockSize)
            let endIndex = startIndex.advanced(by: nextBlockSize)
            let range = startIndex..<endIndex
            startIndex = endIndex
            remainingLength -= nextBlockSize

            let sha = data[range].sha256()
            concatenatedSHAs.append(sha)
            
            if remainingLength == 0 {
                break
            }
        }
        
        let finalSHA = concatenatedSHAs.sha256()
        let hexString = finalSHA.map { String(format: "%02hhx", $0) }.joined()

        return hexString
    }
    
    private static let googleBufferSize = 1024 * 1024
    
    static func generateMD5(fromData data: Data) -> String? {
        if data.count == 0 {
            Log.error("No data!")
            return nil
        }
        
        let result: [UInt8]
        
        do {
            var digest = MD5()
            _ = try data.withUnsafeBytes {
                try digest.update(withBytes: ArraySlice<UInt8>($0))
            }

            result = try digest.finish()
        } catch (let error) {
            Log.error("\(error)")
            return nil
        }
        
        let digest = Data(result)

        let hexString = digest.map { String(format: "%02hhx", $0) }.joined()
        return hexString
    }
    
    static func hashOf(data: Data, for cloudStorageType: CloudStorageType) -> String? {
        switch cloudStorageType {
        case .Dropbox:
            return generateDropbox(fromData: data)
        case .Google:
            return generateMD5(fromData: data)
        }
    }
}
