//
//  HashingTests.swift
//  AccountFileTests
//
//  Created by Christopher G Prince on 8/15/20.
//

import XCTest
@testable import Server
import LoggerAPI
@testable import TestsCommon

class HashingTests: XCTestCase {
    func testDropboxHash() throws {
        let file:TestFile = .test1
        
        let data: Data
        
        switch file.contents {
        case .string(let string):
            guard let result = string.data(using: .utf8) else {
                XCTFail()
                return
            }
            
            data = result
        default:
            XCTFail()
            return
        }
        
        let hash = Hashing.generateDropbox(fromData: data)
        XCTAssert(file.dropboxCheckSum == hash)
    }
    
    func testGoogleHash() throws {
        let file:TestFile = .test1
        
        let data: Data
        
        switch file.contents {
        case .string(let string):
            guard let result = string.data(using: .utf8) else {
                XCTFail()
                return
            }
            
            data = result
        default:
            XCTFail()
            return
        }
        
        let hash = Hashing.generateMD5(fromData: data)
        XCTAssert(file.md5CheckSum == hash)
    }
}
