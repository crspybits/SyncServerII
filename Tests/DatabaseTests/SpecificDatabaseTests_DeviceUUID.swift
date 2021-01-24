//
//  SpecificDatabaseTests_DeviceUUID.swift
//  Server
//
//  Created by Christopher Prince on 12/18/16.
//
//

import XCTest
@testable import Server
@testable import TestsCommon
import LoggerAPI
import HeliumLogger
import Credentials
import CredentialsGoogle
import Foundation
import ServerShared

class SpecificDatabaseTests_DeviceUUID: ServerTestCase {
    override func setUp() {
        super.setUp()
    }
    
    override func tearDown() {
        super.tearDown()
    }
    
    func doAddDeviceUUID(userId:UserId = 1, repo:DeviceUUIDRepository) -> DeviceUUID? {
        let du = DeviceUUID(userId: userId, deviceUUID: Foundation.UUID().uuidString)
        let result = repo.add(deviceUUID: du)
        
        switch result {
        case .error(_), .exceededMaximumUUIDsPerUser:
            return nil
        case .success:
            return du
        }
    }
    
    func testAddDeviceUUID() {
        XCTAssert(doAddDeviceUUID(repo:DeviceUUIDRepository(db)) != nil)
    }
    
    func testAddDeviceUUIDFailsAfterMax() {
        let repo = DeviceUUIDRepository(db)
        if let maxNumber = repo.maximumNumberOfDeviceUUIDsPerUser {
            let number = maxNumber + 1
            for curr in 1...number {
                if curr < number {
                    XCTAssert(doAddDeviceUUID(repo: repo) != nil)
                }
                else {
                    XCTAssert(doAddDeviceUUID(repo: repo) == nil)
                }
            }
        }
    }

    func testAddDeviceUUIDDoesNotFailFailsAfterMaxWithNilMax() {
        let repo = DeviceUUIDRepository(db)
        if let maxNumber = repo.maximumNumberOfDeviceUUIDsPerUser {
            let number = maxNumber + 1
            repo.maximumNumberOfDeviceUUIDsPerUser = nil
            
            for _ in 1...number {
                XCTAssert(doAddDeviceUUID(repo: repo) != nil)
            }
        }
    }
    
    func testLookupFromDeviceUUID() {
        let repo = DeviceUUIDRepository(db)
        let result = doAddDeviceUUID(repo:repo)
        XCTAssert(result != nil)
        let key = DeviceUUIDRepository.LookupKey.deviceUUID(result!.deviceUUID)
        let lookupResult = repo.lookup(key: key, modelInit: DeviceUUID.init)
        
        if case .found(let model) = lookupResult,
            let du = model as? DeviceUUID {
            XCTAssert(du.deviceUUID == result!.deviceUUID)
            XCTAssert(du.userId == result!.userId)
        }
        else {
            XCTFail()
        }
    }
}

