//
//  HealthCheckTests.swift
//  Server
//
//  Created by Christopher Prince on 12/28/17.
//
//

import XCTest
@testable import Server
@testable import TestsCommon
import LoggerAPI
import Foundation
import ServerShared

class HealthCheckTests: ServerTestCase {
    override func setUp() {
        super.setUp()        
    }
    
    func testThatHealthCheckReturnsExpectedInfo() {
        healthCheck()
    }
}


