//
//  Performance.swift
//  SyncServer
//
//  Created by Christopher Prince on 5/21/17.
//  Copyright © 2017 CocoaPods. All rights reserved.
//

import XCTest
@testable import SyncServer

class Performance: TestCase {
    
    override func setUp() {
        super.setUp()
        resetFileMetaData(removeServerFiles: true, actualDeletion: false)
    }
    
    override func tearDown() {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
        super.tearDown()
    }
    
    func downloadNFiles(_ N:UInt, fileName: String, fileExtension:String, mimeType:String) {
        // First upload N files.
        let masterVersion = getMasterVersion()
        let fileURL = Bundle(for: ServerAPI_UploadFile.self).url(forResource: fileName, withExtension: fileExtension)!
        
        for _ in 1...N {
            let fileUUID = UUID().uuidString

            guard let (_, _) = uploadFile(fileURL:fileURL, mimeType: mimeType, fileUUID: fileUUID, serverMasterVersion: masterVersion) else {
                return
            }
        }
        
        doneUploads(masterVersion: masterVersion, expectedNumberUploads: Int64(N))
        
        let expectation = self.expectation(description: "downloadNFiles")
        self.deviceUUID = Foundation.UUID()
        
        shouldSaveDownloads = { downloads in
            XCTAssert(downloads.count == Int(N), "Number of downloads were: \(downloads.count)")
            expectation.fulfill()
        }
        
        // Next, initiate the download using .sync()
        SyncServer.session.sync()
        
        waitForExpectations(timeout: Double(N) * 20.0, handler: nil)
    }
    
    func test10SmallTextFileDownloads() {
        downloadNFiles(10, fileName: "UploadMe", fileExtension:"txt", mimeType: "text/plain")
    }
    
    func test10_120K_ImageFileDownloads() {
        downloadNFiles(10, fileName: "CatBehaviors", fileExtension:"jpg", mimeType:"image/jpeg")
    }
 
    // 5/27/17; I've been having problems with large-ish downloads. E.g., See https://stackoverflow.com/questions/44224048/timeout-issue-when-downloading-from-aws-ec2-to-ios-app
    func test10SmallerImageFileDownloads() {
        downloadNFiles(10, fileName: "SmallerCat", fileExtension:"jpg", mimeType:"image/jpeg")
    }
    
    func test10LargeImageFileDownloads() {
        downloadNFiles(10, fileName: "Cat", fileExtension:"jpg", mimeType:"image/jpeg")
    }
    
    func interspersedDownloadsOfSmallTextFile(_ N:Int) {
        for _ in 1...N {
            doASingleDownloadUsingSync(fileName: "UploadMe", fileExtension:"txt", mimeType: "text/plain")
        }
    }
    
    // TODO: *0* Change this to not allow retries at the ServerAPI or networking level. i.e., so that it fails if a retry was to be required.
    func test10SmallTextFileDownloadsInterspersed() {
        interspersedDownloadsOfSmallTextFile(10)
    }
    
    func deleteNFiles(_ N:UInt, fileName: String, fileExtension:String, mimeType:String) {
        // First upload N files.
        let masterVersion = getMasterVersion()
        let fileURL = Bundle(for: ServerAPI_UploadFile.self).url(forResource: fileName, withExtension: fileExtension)!
        
        var fileUUIDs = [String]()
        
        for _ in 1...N {
            let fileUUID = UUID().uuidString
            fileUUIDs.append(fileUUID)
            
            guard let (_, _) = uploadFile(fileURL:fileURL, mimeType: mimeType, fileUUID: fileUUID, serverMasterVersion: masterVersion) else {
                return
            }
        }
        
        doneUploads(masterVersion: masterVersion, expectedNumberUploads: Int64(N))
        
        for fileIndex in 0...N-1 {
            let fileUUID = fileUUIDs[Int(fileIndex)]

            let fileToDelete = ServerAPI.FileToDelete(fileUUID: fileUUID, fileVersion: 0)
            uploadDeletion(fileToDelete: fileToDelete, masterVersion: masterVersion+1)
        }
        
        doneUploads(masterVersion: masterVersion+1, expectedNumberDeletions: N)
    }
    
    func test10Deletions() {
        deleteNFiles(10, fileName: "UploadMe", fileExtension:"txt", mimeType: "text/plain")
    }
    
    func test50Deletions() {
        deleteNFiles(50, fileName: "UploadMe", fileExtension:"txt", mimeType: "text/plain")
    }
    
    // TODO: *0* Delete 50 files in the same done uploads.
}
