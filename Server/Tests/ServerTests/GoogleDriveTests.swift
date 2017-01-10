//
//  GoogleDriveTests.swift
//  Server
//
//  Created by Christopher Prince on 1/7/17.
//
//

import XCTest
@testable import Server

class GoogleDriveTests: ServerTestCase {
    // A folder known to be in my Google Drive:
    let knownPresentFolder = "Programming"
    
    // Folder known to be absent.
    let knownAbsentFolder = "Markwa.Farkwa.Blarkwa"
    
    override func setUp() {
        super.setUp()
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }
    
    override func tearDown() {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
        super.tearDown()
    }

    func testListFiles() {
        let creds = GoogleCreds()
        creds.refreshToken = self.refreshToken()
        let exp = expectation(description: "\(#function)\(#line)")
        
        creds.refresh { error in
            XCTAssert(error == nil)
            XCTAssert(creds.accessToken != nil)
            
            creds.listFiles { json, error in
                XCTAssert(error == nil)
                XCTAssert((json?.count)! > 0)
                exp.fulfill()
            }
        }

        waitForExpectations(timeout: 10, handler: nil)
    }
    
    func searchForFolder(name:String, presentExpected:Bool) {
        let creds = GoogleCreds()
        creds.refreshToken = self.refreshToken()
        let exp = expectation(description: "\(#function)\(#line)")
        
        creds.refresh { error in
            XCTAssert(error == nil)
            XCTAssert(creds.accessToken != nil)
            
            creds.searchForFolder(folderName: name) { (folderId, error) in
                if presentExpected {
                    XCTAssert(folderId != nil)
                }
                else {
                    XCTAssert(folderId == nil)
                }
                XCTAssert(error == nil)
                exp.fulfill()
            }
        }

        waitForExpectations(timeout: 10, handler: nil)
    }
    
    func testSearchForPresentFolder() {
        searchForFolder(name: self.knownPresentFolder, presentExpected: true)
    }
    
    func testSearchForAbsentFolder() {
        searchForFolder(name: self.knownAbsentFolder, presentExpected: false)
    }
    
    // Haven't been able to get trashFile to work yet.
#if false
    func testTrashFolder() {
        let creds = GoogleCreds()
        creds.refreshToken = self.refreshToken()
        let exp = expectation(description: "\(#function)\(#line)")
        
        creds.refresh { error in
            XCTAssert(error == nil)
            XCTAssert(creds.accessToken != nil)
            
//            creds.createFolder(folderName: "TestMe") { folderId, error in
//                XCTAssert(folderId != nil)
//                XCTAssert(error == nil)
            
                let folderId = "0B3xI3Shw5ptRdWtPR3ZLdXpqbHc"
                creds.trashFile(fileId: folderId) { error in
                    XCTAssert(error == nil)
                    exp.fulfill()
                }
//            }
        }

        waitForExpectations(timeout: 10, handler: nil)
    }
#endif

    func testCreateAndDeleteFolder() {
        let creds = GoogleCreds()
        creds.refreshToken = self.refreshToken()
        let exp = expectation(description: "\(#function)\(#line)")
        
        creds.refresh { error in
            XCTAssert(error == nil)
            XCTAssert(creds.accessToken != nil)
            
            creds.createFolder(folderName: "TestMe") { folderId, error in
                XCTAssert(folderId != nil)
                XCTAssert(error == nil)
            
                creds.deleteFile(fileId: folderId!) { error in
                    XCTAssert(error == nil)
                    exp.fulfill()
                }
            }
        }

        waitForExpectations(timeout: 10, handler: nil)
    }
    
    func testDeleteFolderFailure() {
        let creds = GoogleCreds()
        creds.refreshToken = self.refreshToken()
        let exp = expectation(description: "\(#function)\(#line)")
        
        creds.refresh { error in
            XCTAssert(error == nil)
            XCTAssert(creds.accessToken != nil)
            
            creds.deleteFile(fileId: "foobar") { error in
                XCTAssert(error != nil)
                exp.fulfill()
            }
        }

        waitForExpectations(timeout: 10, handler: nil)
    }
}
