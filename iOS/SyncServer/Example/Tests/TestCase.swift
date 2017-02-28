//
//  TestCase.swift
//  SyncServer
//
//  Created by Christopher Prince on 1/31/17.
//  Copyright © 2017 Spastic Muffin, LLC. All rights reserved.
//

import XCTest
import Foundation
@testable import SyncServer
import SMCoreLib

class TestCase: XCTestCase {
    let cloudFolderName = "Test.Folder"
    var authTokens = [String:String]()
    
    var deviceUUID = Foundation.UUID()
    var deviceUUIDCalled:Bool = false
    
    var testLockSync: TimeInterval?
    var testLockSyncCalled:Bool = false

    // This value needs to be refreshed before running these tests.
    static let accessToken:String = {
        let plist = try! PlistDictLoader(plistFileNameInBundle: Consts.serverPlistFile)
        
        if case .stringValue(let value) = try! plist.getRequired(varName: "GoogleAccessToken") {
            return value
        }
        
        XCTFail()
        return ""
    }()
    
    override func setUp() {
        super.setUp()
        ServerAPI.session.delegate = self
        ServerNetworking.session.authenticationDelegate = self
        
        self.authTokens = [
            ServerConstants.XTokenTypeKey: ServerConstants.AuthTokenType.GoogleToken.rawValue,
            ServerConstants.GoogleHTTPAccessTokenKey: TestCase.accessToken
        ]
    }
    
    override func tearDown() {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
        super.tearDown()
    }
    
    func getMasterVersion() -> MasterVersionInt {
        let expectation1 = self.expectation(description: "fileIndex")

        var serverMasterVersion:MasterVersionInt = 0
        
        ServerAPI.session.fileIndex { (fileIndex, masterVersion, error) in
            XCTAssert(error == nil)
            XCTAssert(masterVersion! >= 0)
            serverMasterVersion = masterVersion!
            expectation1.fulfill()
        }
        
        waitForExpectations(timeout: 10.0, handler: nil)
        
        return serverMasterVersion
    }
    
    func getFileIndex(expectedFiles:[(fileUUID:String, fileSize:Int64)], callback:((FileInfo)->())? = nil) {
        let expectation1 = self.expectation(description: "fileIndex")
        
        ServerAPI.session.fileIndex { (fileIndex, masterVersion, error) in
            XCTAssert(error == nil)
            XCTAssert(masterVersion! >= 0)
            
            for (fileUUID, fileSize) in expectedFiles {
                let result = fileIndex?.filter { file in
                    file.fileUUID == fileUUID
                }
                
                XCTAssert(result!.count == 1)
                XCTAssert(result![0].fileSizeBytes == fileSize)
            }
            
            for curr in 0..<fileIndex!.count {
                callback?(fileIndex![curr])
            }
            
            expectation1.fulfill()
        }
        
        waitForExpectations(timeout: 10.0, handler: nil)
    }
    
    func getUploads(expectedFiles:[(fileUUID:String, fileSize:Int64?)], callback:((FileInfo)->())? = nil) {
        let expectation1 = self.expectation(description: "getUploads")
        
        ServerAPI.session.getUploads { (uploads, error) in
            XCTAssert(error == nil)
            
            XCTAssert(expectedFiles.count == uploads?.count)
            
            for (fileUUID, fileSize) in expectedFiles {
                let result = uploads?.filter { file in
                    file.fileUUID == fileUUID
                }
                
                XCTAssert(result!.count == 1)
                if fileSize != nil {
                    XCTAssert(result![0].fileSizeBytes == fileSize)
                }
            }
            
            for curr in 0..<uploads!.count {
                callback?(uploads![curr])
            }
            
            expectation1.fulfill()
        }
        
        waitForExpectations(timeout: 10.0, handler: nil)
    }
    
    // Returns the file size uploaded
    func uploadFile(fileName:String, fileExtension:String, mimeType:String, fileUUID:String = UUID().uuidString, serverMasterVersion:MasterVersionInt = 0, expectError:Bool = false, appMetaData:String? = nil) -> (fileSize: Int64, ServerAPI.File)? {
    
        let fileURL = Bundle(for: ServerAPI_UploadFile.self).url(forResource: fileName, withExtension: fileExtension)!

        let file = ServerAPI.File(localURL: fileURL, fileUUID: fileUUID, mimeType: mimeType, cloudFolderName: cloudFolderName, deviceUUID: deviceUUID.uuidString, appMetaData: appMetaData, fileVersion: 0)
        
        // Just to get the size-- this is redundant with the file read in ServerAPI.session.uploadFile
        guard let fileData = try? Data(contentsOf: file.localURL) else {
            XCTFail()
            return nil
        }
        
        let expectation = self.expectation(description: "upload")
        var fileSize:Int64?
        
        ServerAPI.session.uploadFile(file: file, serverMasterVersion: serverMasterVersion) { uploadFileResult, error in
            if expectError {
                XCTAssert(error != nil)
            }
            else {
                XCTAssert(error == nil)
                if case .success(let size) = uploadFileResult! {
                    XCTAssert(Int64(fileData.count) == size)
                    fileSize = size
                }
                else {
                    XCTFail()
                }
            }
            
            expectation.fulfill()
        }
        
        waitForExpectations(timeout: 30.0, handler: nil)
        
        if fileSize == nil {
            return nil
        }
        else {
            return (fileSize!, file)
        }
    }
    
    func uploadFile(fileName:String, fileExtension:String, mimeType:String, fileUUID:String = UUID().uuidString, serverMasterVersion:MasterVersionInt = 0, withExpectation expectation:XCTestExpectation) {
    
        let fileURL = Bundle(for: ServerAPI_UploadFile.self).url(forResource: fileName, withExtension: fileExtension)!

        let file = ServerAPI.File(localURL: fileURL, fileUUID: fileUUID, mimeType: mimeType, cloudFolderName: cloudFolderName, deviceUUID: deviceUUID.uuidString, appMetaData: nil, fileVersion: 0)
        
        // Just to get the size-- this is redundant with the file read in ServerAPI.session.uploadFile
        guard let fileData = try? Data(contentsOf: file.localURL) else {
            XCTFail()
            return
        }
        
        Log.special("ServerAPI.session.uploadFile")
        
        ServerAPI.session.uploadFile(file: file, serverMasterVersion: serverMasterVersion) { uploadFileResult, error in
        
            XCTAssert(error == nil)
            if case .success(let size) = uploadFileResult! {
                XCTAssert(Int64(fileData.count) == size)
            }
            else {
                XCTFail()
            }
            
            expectation.fulfill()
        }
    }
    
    func doneUploads(masterVersion: MasterVersionInt, expectedNumberUploads:Int64) {
        let expectation = self.expectation(description: "doneUploads")

        ServerAPI.session.doneUploads(serverMasterVersion: masterVersion) {
            doneUploadsResult, error in
            
            XCTAssert(error == nil)
            if case .success(let numberUploads) = doneUploadsResult! {
                XCTAssert(numberUploads == expectedNumberUploads)
            }
            else {
                XCTFail()
            }
            
            expectation.fulfill()
        }
        
        waitForExpectations(timeout: 10.0, handler: nil)
    }
    
    func removeAllServerFilesInFileIndex() {
        let masterVersion = getMasterVersion()
        
        var filesToDelete:[FileInfo]?
        let uploadDeletion = self.expectation(description: "uploadDeletion")

        func recursiveRemoval(indexToRemove:Int) {
            if indexToRemove >= filesToDelete!.count {
                uploadDeletion.fulfill()
                return
            }
            
            let fileIndexObj = filesToDelete![indexToRemove]
            var fileToDelete = ServerAPI.FileToDelete(fileUUID: fileIndexObj.fileUUID, fileVersion: fileIndexObj.fileVersion)
            fileToDelete.actualDeletion = true
            
            ServerAPI.session.uploadDeletion(file: fileToDelete, serverMasterVersion: masterVersion) { (result, error) in
                XCTAssert(error == nil)
                guard case .success = result! else {
                    XCTFail()
                    return
                }
                
                recursiveRemoval(indexToRemove: indexToRemove + 1)
            }
        }
        
        ServerAPI.session.fileIndex { (fileIndex, masterVersion, error) in
            XCTAssert(error == nil)
            XCTAssert(masterVersion! >= 0)
            
            filesToDelete = fileIndex
            recursiveRemoval(indexToRemove: 0)
        }
        
        waitForExpectations(timeout: 30.0, handler: nil)
    }
    
    func filesHaveSameContents(url1: URL, url2: URL) -> Bool {
        
        let fileData1 = try? Data(contentsOf: url1 as URL)
        let fileData2 = try? Data(contentsOf: url2 as URL)
        
        if fileData1 == nil || fileData2 == nil {
            return false
        }
        
        return fileData1! == fileData2!
    }
}

extension TestCase : ServerNetworkingAuthentication {
    func headerAuthentication(forServerNetworking: ServerNetworking) -> [String:String]? {
        var result = [String:String]()
        for (key, value) in self.authTokens {
            result[key] = value
        }
        
        result[ServerConstants.httpRequestDeviceUUID] = self.deviceUUID.uuidString
        
        return result
    }
}

extension TestCase : ServerAPIDelegate {
    func doneUploadsRequestTestLockSync() -> TimeInterval? {
        testLockSyncCalled = true
        return testLockSync
    }
    
    func deviceUUID(forServerAPI: ServerAPI) -> Foundation.UUID {
        deviceUUIDCalled = true
        return deviceUUID
    }
}
