//
//  ServerAPI_DownloadFile.swift
//  SyncServer
//
//  Created by Christopher Prince on 2/12/17.
//  Copyright © 2017 Spastic Muffin, LLC. All rights reserved.
//

import XCTest
@testable import SyncServer

class ServerAPI_DownloadFile: TestCase {
    
    override func setUp() {
        super.setUp()
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }
    
    override func tearDown() {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
        super.tearDown()
    }
    
    func testDownloadTextFile() {
        uploadAndDownloadTextFile()
    }
    
    func testDownloadTextFileWithAppMetaData() {
        uploadAndDownloadTextFile(appMetaData: "foobar was here")
    }
    
    // TODO: *1* Test that two concurrent downloads work.
}
