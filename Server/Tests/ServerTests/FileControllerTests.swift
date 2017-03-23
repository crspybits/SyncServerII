//
//  FileControllerTests.swift
//  Server
//
//  Created by Christopher Prince on 1/15/17.
//
//

import XCTest
@testable import Server
import LoggerAPI
import PerfectLib

class FileControllerTests: ServerTestCase {

    override func setUp() {
        super.setUp()
    }
    
    override func tearDown() {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
        super.tearDown()
    }
      
    // A test that causes a conflict with the master version on the server. Presumably this needs to take the form of (a) device1 uploading a file to the server, (b) device2 uploading a file, and finishing that upload (`DoneUploads` endpoint), and (c) device1 uploading a second file using its original master version.
    func testMasterVersionConflict1() {
        let deviceUUID1 = PerfectLib.UUID().string
        _ = uploadTextFile(deviceUUID:deviceUUID1)
        
        let deviceUUID2 = PerfectLib.UUID().string
        _ = uploadTextFile(deviceUUID:deviceUUID2, addUser:false)
        
        self.sendDoneUploads(expectedNumberOfUploads: 1, deviceUUID:deviceUUID2)
        
        _ = uploadTextFile(deviceUUID:deviceUUID2, addUser:false, updatedMasterVersionExpected:1)
    }
    
    func testMasterVersionConflict2() {
        let deviceUUID1 = PerfectLib.UUID().string
        _ = uploadTextFile(deviceUUID:deviceUUID1)
        
        let deviceUUID2 = PerfectLib.UUID().string
        _ = uploadTextFile(deviceUUID:deviceUUID2, addUser:false)
        
        self.sendDoneUploads(expectedNumberOfUploads: 1, deviceUUID:deviceUUID1)
        
        // No uploads should have been successfully finished, i.e., expectedNumberOfUploads = nil, and the updatedMasterVersion should have been updated to 1.
        self.sendDoneUploads(expectedNumberOfUploads: nil, deviceUUID:deviceUUID2, updatedMasterVersionExpected:1)
    }

    // MARK: DoneUploads tests
    
    func testDoneUploadsWithNoUploads() {
        let deviceUUID = PerfectLib.UUID().string
        self.addNewUser(deviceUUID:deviceUUID)
        self.sendDoneUploads(expectedNumberOfUploads: 0)
    }
    
    func testDoneUploadsWithSingleUpload() {
        let deviceUUID = PerfectLib.UUID().string
        _ = uploadTextFile(deviceUUID:deviceUUID)
        self.sendDoneUploads(expectedNumberOfUploads: 1, deviceUUID:deviceUUID)
    }
    
    func testDoneUploadsWithTwoUploads() {
        let deviceUUID = PerfectLib.UUID().string
        _ = uploadTextFile(deviceUUID:deviceUUID)
        _ = uploadJPEGFile(deviceUUID:deviceUUID, addUser:false)
        self.sendDoneUploads(expectedNumberOfUploads: 2, deviceUUID:deviceUUID)
    }
    
    func testDoneUploadsThatUpdatesFileVersion() {
        let deviceUUID = PerfectLib.UUID().string
        let fileUUID = PerfectLib.UUID().string
        
        _ = uploadTextFile(deviceUUID:deviceUUID, fileUUID:fileUUID)
        self.sendDoneUploads(expectedNumberOfUploads: 1, deviceUUID:deviceUUID)
        
        _ = uploadTextFile(deviceUUID:deviceUUID, fileUUID:fileUUID, addUser:false, fileVersion:1, masterVersion: 1)
        self.sendDoneUploads(expectedNumberOfUploads: 1, deviceUUID:deviceUUID, masterVersion: 1)
    }
    
    func testFileIndexWithNoFiles() {
        let deviceUUID = PerfectLib.UUID().string

        self.addNewUser(deviceUUID:deviceUUID)
        self.getFileIndex(expectedFiles: [], masterVersionExpected: 0, expectedFileSizes: [:])
    }
    
    func testFileIndexWithOneFile() {
        let deviceUUID = PerfectLib.UUID().string
        let (uploadRequest, fileSize) = uploadTextFile(deviceUUID:deviceUUID)
        
        // Have to do a DoneUploads to transfer the files into the FileIndex
        self.sendDoneUploads(expectedNumberOfUploads: 1, deviceUUID:deviceUUID)

        let expectedSizes = [
            uploadRequest.fileUUID: fileSize,
        ]
        
        self.getFileIndex(expectedFiles: [uploadRequest], masterVersionExpected: 1, expectedFileSizes: expectedSizes)
    }
    
    func testFileIndexWithTwoFiles() {
        let deviceUUID = PerfectLib.UUID().string
        let (uploadRequest1, fileSize1) = uploadTextFile(deviceUUID:deviceUUID)
        let (uploadRequest2, fileSize2) = uploadJPEGFile(deviceUUID:deviceUUID, addUser:false)
        
        // Have to do a DoneUploads to transfer the files into the FileIndex
        self.sendDoneUploads(expectedNumberOfUploads: 2, deviceUUID:deviceUUID)

        let expectedSizes = [
            uploadRequest1.fileUUID: fileSize1,
            uploadRequest2.fileUUID: fileSize2
        ]
        
        self.getFileIndex(expectedFiles: [uploadRequest1, uploadRequest2],masterVersionExpected: 1, expectedFileSizes: expectedSizes)
    }
    
    func downloadTextFile(masterVersionExpectedWithDownload:Int, expectUpdatedMasterUpdate:Bool = false, appMetaData:String? = nil, uploadFileVersion:FileVersionInt = 0, downloadFileVersion:Int64 = 0, expectedError: Bool = false) {
    
        let deviceUUID = PerfectLib.UUID().string
        let masterVersion:Int64 = 0
        let (uploadRequest, fileSize) = uploadTextFile(deviceUUID:deviceUUID, fileVersion:uploadFileVersion, masterVersion:masterVersion, cloudFolderName: self.testFolder, appMetaData:appMetaData)
        self.sendDoneUploads(expectedNumberOfUploads: 1, deviceUUID:deviceUUID, masterVersion: masterVersion)
        
        self.performServerTest { expectation, googleCreds in
            let headers = self.setupHeaders(accessToken: googleCreds.accessToken, deviceUUID:deviceUUID)
            
            let downloadFileRequest = DownloadFileRequest(json: [
                DownloadFileRequest.fileUUIDKey: uploadRequest.fileUUID,
                DownloadFileRequest.masterVersionKey : "\(masterVersionExpectedWithDownload)",
                DownloadFileRequest.fileVersionKey : downloadFileVersion
            ])
            
            self.performRequest(route: ServerEndpoints.downloadFile, responseDictFrom:.header, headers: headers, urlParameters: "?" + downloadFileRequest!.urlParameters()!, body:nil) { response, dict in
                Log.info("Status code: \(response!.statusCode)")
                
                if expectedError {
                    XCTAssert(response!.statusCode != .OK, "Did not work on failing downloadFileRequest request")
                    XCTAssert(dict == nil)
                }
                else {
                    XCTAssert(response!.statusCode == .OK, "Did not work on downloadFileRequest request")
                    XCTAssert(dict != nil)
                    
                    if let downloadFileResponse = DownloadFileResponse(json: dict!) {
                        if expectUpdatedMasterUpdate {
                            XCTAssert(downloadFileResponse.masterVersionUpdate != nil)
                        }
                        else {
                            XCTAssert(downloadFileResponse.masterVersionUpdate == nil)
                            XCTAssert(downloadFileResponse.fileSizeBytes == fileSize)
                            XCTAssert(downloadFileResponse.appMetaData == appMetaData)
                        }
                    }
                    else {
                        XCTFail()
                    }
                }
                
                expectation.fulfill()
            }
        }
    }
    
    func testDownloadFileTextSucceeds() {
        downloadTextFile(masterVersionExpectedWithDownload: 1)
    }
    
    func testDownloadFileTextWhereMasterVersionDiffersFails() {
        downloadTextFile(masterVersionExpectedWithDownload: 0, expectUpdatedMasterUpdate:true)
    }
    
    func testDownloadFileTextWithAppMetaDataSucceeds() {
        downloadTextFile(masterVersionExpectedWithDownload: 1,
            appMetaData:"{ \"foo\": \"bar\" }")
    }
    
    func testDownloadFileTextWithDifferentDownloadVersion() {
        downloadTextFile(masterVersionExpectedWithDownload: 1, downloadFileVersion:1, expectedError: true)
    }
    
    // TODO: *0*: Make sure we're not trying to download a file that has already been deleted.
    
    // TODO: *1* Make sure its an error for a different user to download our file even if they have the fileUUID and fileVersion.
    
    // TODO: *1* Test that two concurrent downloads work.
}

