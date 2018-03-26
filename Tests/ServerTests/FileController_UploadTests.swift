//
//  FileController_UploadTests.swift
//  Server
//
//  Created by Christopher Prince on 3/22/17.
//
//

import XCTest
@testable import Server
import LoggerAPI
import Foundation
import PerfectLib
import SyncServerShared

class FileController_UploadTests: ServerTestCase, LinuxTestable {

    override func setUp() {
        super.setUp()
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }
    
    override func tearDown() {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
        super.tearDown()
    }
    
    func testUploadTextFile() {
        _ = uploadTextFile()
    }
    
    func testUploadJPEGFile() {
        _ = uploadJPEGFile()
    }
    
    func testUploadTextAndJPEGFile() {
        let deviceUUID = PerfectLib.UUID().string
        _ = uploadTextFile(deviceUUID:deviceUUID)
        
        guard let _ = uploadJPEGFile(deviceUUID:deviceUUID, addUser:false) else {
            XCTFail()
            return
        }
    }
    
    func testUploadingSameFileTwiceWorks() {
        let deviceUUID = PerfectLib.UUID().string
        let (request, _) = uploadTextFile(deviceUUID:deviceUUID)
        
        // Second upload.
        _ = uploadTextFile(deviceUUID: deviceUUID, fileUUID: request.fileUUID, addUser: false, fileVersion: request.fileVersion, masterVersion: request.masterVersion, appMetaData: request.appMetaData)
    }

    func testUploadTextFileWithStringWithSpacesAppMetaData() {
        _ = uploadTextFile(appMetaData:AppMetaData(version: 0, contents: "A Simple String"))
    }
    
    func testUploadTextFileWithJSONAppMetaData() {
        _ = uploadTextFile(appMetaData:AppMetaData(version: 0, contents: "{ \"foo\": \"bar\" }"))
    }
    
    func testUploadWithInvalidMimeTypeFails() {
        let testAccount:TestAccount = .primaryOwningAccount
        let deviceUUID = PerfectLib.UUID().string
        addNewUser(deviceUUID:deviceUUID, cloudFolderName: ServerTestCase.cloudFolderName)
        
        let fileUUIDToSend = PerfectLib.UUID().string
        
        let uploadString = ServerTestCase.uploadTextFileContents
        let data = ServerTestCase.uploadTextFileContents.data(using: .utf8)!
        
        let uploadRequest = UploadFileRequest(json: [
            UploadFileRequest.fileUUIDKey : fileUUIDToSend,
            UploadFileRequest.mimeTypeKey: "foobar",
            UploadFileRequest.fileVersionKey: 0,
            UploadFileRequest.masterVersionKey: 0
        ])!
        
        runUploadTest(testAccount:testAccount, data:data, uploadRequest:uploadRequest, expectedUploadSize:Int64(uploadString.count), deviceUUID:deviceUUID, errorExpected: true)
    }
}

extension FileController_UploadTests {
    static var allTests : [(String, (FileController_UploadTests) -> () throws -> Void)] {
        return [
            ("testUploadTextFile", testUploadTextFile),
            ("testUploadJPEGFile", testUploadJPEGFile),
            ("testUploadTextAndJPEGFile", testUploadTextAndJPEGFile),
            ("testUploadingSameFileTwiceWorks", testUploadingSameFileTwiceWorks),
            ("testUploadTextFileWithStringWithSpacesAppMetaData", testUploadTextFileWithStringWithSpacesAppMetaData),
            ("testUploadTextFileWithJSONAppMetaData", testUploadTextFileWithJSONAppMetaData),
            ("testUploadWithInvalidMimeTypeFails", testUploadWithInvalidMimeTypeFails)
        ]
    }
    
    func testLinuxTestSuiteIncludesAllTests() {
        linuxTestSuiteIncludesAllTests(testType:FileController_UploadTests.self)
    }
}
