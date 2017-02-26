//
//  CoreDataTests.swift
//  SyncServer
//
//  Created by Christopher Prince on 2/25/17.
//  Copyright © 2017 CocoaPods. All rights reserved.
//

import XCTest
@testable import SyncServer
import SMCoreLib

class CoreDataTests: TestCase {
    
    override func setUp() {
        super.setUp()
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }
    
    override func tearDown() {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
        super.tearDown()
    }
    
    func testLocalURLOnDownloadFileTracker() {
        let obj = DownloadFileTracker.newObject() as! DownloadFileTracker
        obj.localURL = SMRelativeLocalURL(withRelativePath: "foobar", toBaseURLType: .documentsDirectory)
        XCTAssert(obj.localURL != nil)
    }
}
