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

    // A cloud folder name
    let testFolder = "Test.Folder"

    override func setUp() {
        super.setUp()
        _ = UserRepository(db).remove()
        _ = UserRepository(db).create()
        _ = UploadRepository(db).remove()
        _ = UploadRepository(db).create()
        _ = MasterVersionRepository(db).remove()
        _ = MasterVersionRepository(db).create()
        _ = FileIndexRepository(db).remove()
        _ = FileIndexRepository(db).create()
        _ = LockRepository(db).remove()
        _ = LockRepository(db).create()
    }
    
    override func tearDown() {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
        super.tearDown()
    }

    func runUploadTest(data:Data, uploadRequest:UploadFileRequest, expectedUploadSize:Int64, updatedMasterVersionExpected:Int64? = nil) {
        self.performServerTest { expectation, googleCreds in
            let headers = self.setupHeaders(accessToken: googleCreds.accessToken)
            
            // The method for ServerEndpoints.uploadFile really must be a POST to upload the file.
            XCTAssert(ServerEndpoints.uploadFile.method == .post)
            
            self.performRequest(route: ServerEndpoints.uploadFile, headers: headers, urlParameters: "?" + uploadRequest.urlParameters()!, body:data) { response, dict in
                Log.info("Status code: \(response!.statusCode)")
                XCTAssert(response!.statusCode == .OK, "Did not work on uploadFile request")
                XCTAssert(dict != nil)
                
                if let uploadResponse = UploadFileResponse(json: dict!) {
                    if updatedMasterVersionExpected == nil {
                        XCTAssert(uploadResponse.size != nil)
                        XCTAssert(uploadResponse.size == expectedUploadSize)
                    }
                    else {
                        XCTAssert(uploadResponse.masterVersionUpdate == updatedMasterVersionExpected)
                    }
                }
                else {
                    XCTFail()
                }
                
                // [1]. 2/11/16. Once I put transaction support into mySQL access, I run into some apparent race conditions with using `UploadRepository(self.db).lookup` here. That is, I fail the following check -- but I don't fail if I put a breakpoint here. This has lead me want to implement a new endpoint-- "GetUploads"-- which will enable (a) testing of the scenario below (i.e., after an upload, making sure that the Upload table has the relevant contents), and (b) recovery in an app when the masterVersion comes back different-- so that some uploaded files might not need to be uploaded again (note that for most purposes this later issue is an optimization).
                /*
                // Check the upload repo to make sure the entry is present.
                Log.debug("uploadRequest.fileUUID: \(uploadRequest.fileUUID)")
                let result = UploadRepository(self.db).lookup(key: .fileUUID(uploadRequest.fileUUID), modelInit: Upload.init)
                switch result {
                case .error(let error):
                    XCTFail("\(error)")
                    
                case .found(_):
                    if updatedMasterVersionExpected != nil {
                        XCTFail("No Upload Found")
                    }

                case .noObjectFound:
                    if updatedMasterVersionExpected == nil {
                        XCTFail("No Upload Found")
                    }
                }*/

                expectation.fulfill()
            }
        }
    }
    
    func uploadTextFile(deviceUUID:String = PerfectLib.UUID().string, fileUUID:String? = nil, addUser:Bool=true, updatedMasterVersionExpected:Int64? = nil, fileVersion:Int64 = 0, masterVersion:Int64 = 0, cloudFolderName:String = "CloudFolder", appMetaData:String? = nil) -> (request: UploadFileRequest, fileSize:Int64) {
        if addUser {
            self.addNewUser()
        }
        
        var fileUUIDToSend = ""
        if fileUUID == nil {
            fileUUIDToSend = PerfectLib.UUID().string
        }
        else {
            fileUUIDToSend = fileUUID!
        }
        
        let stringToUpload = "Hello World!"
        let data = stringToUpload.data(using: .utf8)
        
        let uploadRequest = UploadFileRequest(json: [
            UploadFileRequest.fileUUIDKey : fileUUIDToSend,
            UploadFileRequest.mimeTypeKey: "text/plain",
            UploadFileRequest.cloudFolderNameKey: cloudFolderName,
            UploadFileRequest.deviceUUIDKey: deviceUUID,
            UploadFileRequest.fileVersionKey: fileVersion,
            UploadFileRequest.masterVersionKey: masterVersion
        ])!
        
        uploadRequest.appMetaData = appMetaData
        
        runUploadTest(data:data!, uploadRequest:uploadRequest, expectedUploadSize:Int64(stringToUpload.characters.count), updatedMasterVersionExpected:updatedMasterVersionExpected)
        
        return (request:uploadRequest, fileSize: Int64(stringToUpload.characters.count))
    }
    
    func testUploadTextFile() {
        _ = uploadTextFile()
    }
    
    func uploadJPEGFile(deviceUUID:String = PerfectLib.UUID().string, addUser:Bool=true, fileVersion:Int64 = 0) -> (request: UploadFileRequest, fileSize:Int64) {
    
        if addUser {
            self.addNewUser()
        }
        
        let fileURL = URL(fileURLWithPath: "/tmp/Cat.jpg")
        let sizeOfCatFileInBytes:Int64 = 1162662
        let data = try! Data(contentsOf: fileURL)
        
        let uploadRequest = UploadFileRequest(json: [
            UploadFileRequest.fileUUIDKey : PerfectLib.UUID().string,
            UploadFileRequest.mimeTypeKey: "image/jpeg",
            UploadFileRequest.cloudFolderNameKey: testFolder,
            UploadFileRequest.fileVersionKey: fileVersion,
            UploadFileRequest.deviceUUIDKey: deviceUUID,
            UploadFileRequest.masterVersionKey: 0
        ])
        
        runUploadTest(data:data, uploadRequest:uploadRequest!, expectedUploadSize:sizeOfCatFileInBytes)
        
        return (uploadRequest!, sizeOfCatFileInBytes)
    }
    
    func testUploadJPEGFile() {
        _ = uploadJPEGFile()
    }
    
    func testUploadTextAndJPEGFile() {
        let deviceUUID = PerfectLib.UUID().string
        _ = uploadTextFile(deviceUUID:deviceUUID)
        _ = uploadJPEGFile(deviceUUID:deviceUUID, addUser:false)
    }
    
    func testUploadTextFileWithStringWithSpacesAppMetaData() {
        _ = uploadTextFile(appMetaData:"A Simple String")
    }
    
    func testUploadTextFileWithJSONAppMetaData() {
        _ = uploadTextFile(appMetaData:"{ \"foo\": \"bar\" }")
    }
    
    func sendDoneUploads(expectedNumberOfUploads:Int32?, deviceUUID:String = PerfectLib.UUID().string, updatedMasterVersionExpected:Int64? = nil, masterVersion:Int64 = 0) {
        self.performServerTest { expectation, googleCreds in
            let headers = self.setupHeaders(accessToken: googleCreds.accessToken)
            
            let doneUploadsRequest = DoneUploadsRequest(json: [
                DoneUploadsRequest.deviceUUIDKey: deviceUUID,
                DoneUploadsRequest.masterVersionKey : "\(masterVersion)"
            ])
            
            self.performRequest(route: ServerEndpoints.doneUploads, headers: headers, urlParameters: "?" + doneUploadsRequest!.urlParameters()!, body:nil) { response, dict in
                Log.info("Status code: \(response!.statusCode)")
                XCTAssert(response!.statusCode == .OK, "Did not work on doneUploadsRequest request")
                XCTAssert(dict != nil)
                
                if let doneUploadsResponse = DoneUploadsResponse(json: dict!) {
                    XCTAssert(doneUploadsResponse.masterVersionUpdate == updatedMasterVersionExpected)
                    XCTAssert(doneUploadsResponse.numberUploadsTransferred == expectedNumberOfUploads)
                }
                else {
                    XCTFail()
                }
                
                expectation.fulfill()
            }
        }
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

#if false
    func testLockOnDoneUploadsWorks() {
        let deviceUUID1 = PerfectLib.UUID().string
        _ = uploadTextFile(deviceUUID:deviceUUID1)
        
        let deviceUUID2 = PerfectLib.UUID().string
        _ = uploadTextFile(deviceUUID:deviceUUID2, addUser:false)
        
        let expectation2 = self.expectation(description: "Second")

        self.performServerTest { expectation, googleCreds in
            let headers = self.setupHeaders(accessToken: googleCreds.accessToken)
            
            let doneUploadsRequest1 = DoneUploadsRequest(json: [
                DoneUploadsRequest.deviceUUIDKey: deviceUUID1,
                DoneUploadsRequest.masterVersionKey : "0"
            ])
            
            doneUploadsRequest1!.testLockSync = 5 // seconds
        
            var doneRequest1 = false
            
            DispatchQueue.global(qos: .userInitiated).async {
                // This request will be delayed for 5 seconds because of testLockSync.a`
                self.performRequest(route: ServerEndpoints.doneUploads, headers: headers, urlParameters: "?" + doneUploadsRequest1!.urlParameters()!, body:nil) { response, dict in
                    Log.info("Done Request1: Status code: \(response!.statusCode)")
                    XCTAssert(response!.statusCode == .OK, "Did not work on doneUploadsRequest request")
                    XCTAssert(dict != nil)
                    
                    doneRequest1 = true
                    
                    if let doneUploadsResponse = DoneUploadsResponse(json: dict!) {
                        XCTAssert(doneUploadsResponse.masterVersionUpdate == nil)
                        XCTAssert(doneUploadsResponse.numberUploadsTransferred == 1)
                    }
                    else {
                        XCTFail()
                    }
                    
                    expectation.fulfill()
                }
            }

            // Let above request get started.
            Thread.sleep(forTimeInterval: 1)
            
            let doneUploadsRequest2 = DoneUploadsRequest(json: [
                DoneUploadsRequest.deviceUUIDKey: deviceUUID2,
                DoneUploadsRequest.masterVersionKey : "0"
            ])

            self.performRequest(route: ServerEndpoints.doneUploads, headers: headers, urlParameters: "?" + doneUploadsRequest2!.urlParameters()!, body:nil) { response, dict in
                Log.info("Done Request2: Status code: \(response!.statusCode)")
                XCTAssert(response!.statusCode != .OK, "doneUploadsRequest request succeeded!")
                
                // We should complete this request *before* the first request.
                XCTAssert(!doneRequest1)
                
                expectation2.fulfill()
            }
        }
    }
#endif

    // MARK: DoneUploads tests
    
    func testDoneUploadsWithNoUploads() {
        self.addNewUser()
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
    
    func getFileIndex(expectedFiles:[UploadFileRequest], deviceUUID:String = PerfectLib.UUID().string, masterVersionExpected:Int64, expectedFileSizes: [String: Int64]) {
    
        XCTAssert(expectedFiles.count == expectedFileSizes.count)
        
        self.performServerTest { expectation, googleCreds in
            let headers = self.setupHeaders(accessToken: googleCreds.accessToken)
            
            let fileIndexRequest = FileIndexRequest(json: [
                FileIndexRequest.deviceUUIDKey: deviceUUID
            ])
        
            self.performRequest(route: ServerEndpoints.fileIndex, headers: headers, urlParameters: "?" + fileIndexRequest!.urlParameters()!, body:nil) { response, dict in
                Log.info("Status code: \(response!.statusCode)")
                XCTAssert(response!.statusCode == .OK, "Did not work on fileIndexRequest request")
                XCTAssert(dict != nil)
                
                if let fileIndexResponse = FileIndexResponse(json: dict!) {
                    XCTAssert(fileIndexResponse.masterVersion == masterVersionExpected)
                    XCTAssert(fileIndexResponse.fileIndex!.count == expectedFiles.count)
                    
                    _ = fileIndexResponse.fileIndex!.map { fileInfo in
                        Log.info("fileInfo: \(fileInfo)")
                        
                        let filterResult = expectedFiles.filter { uploadFileRequest in
                            uploadFileRequest.fileUUID == fileInfo.fileUUID
                        }
                        
                        XCTAssert(filterResult.count == 1)
                        let expectedFile = filterResult[0]
                        
                        XCTAssert(expectedFile.appMetaData == fileInfo.appMetaData)
                        XCTAssert(expectedFile.fileUUID == fileInfo.fileUUID)
                        XCTAssert(expectedFile.fileVersion == fileInfo.fileVersion)
                        XCTAssert(expectedFile.mimeType == fileInfo.mimeType)
                        XCTAssert(fileInfo.deleted == false)
                        
                        XCTAssert(expectedFileSizes[fileInfo.fileUUID] == fileInfo.fileSizeBytes)
                    }
                }
                else {
                    XCTFail()
                }
                
                expectation.fulfill()
            }
        }
    }
    
    func testFileIndexWithNoFiles() {
        self.addNewUser()
        self.getFileIndex(expectedFiles: [], masterVersionExpected: 0, expectedFileSizes: [:])
    }
    
    func testFileIndexWithOneFile() {
        let deviceUUID = PerfectLib.UUID().string
        let (uploadRequest, fileSize) = uploadTextFile(deviceUUID:deviceUUID)
        
        // Have to a DoneUploads to transfer the files into the FileIndex
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
        
        self.getFileIndex(expectedFiles: [uploadRequest1, uploadRequest2], masterVersionExpected: 1, expectedFileSizes: expectedSizes)
    }
    
    func downloadTextFile(masterVersionExpectedWithDownload:Int, expectUpdatedMasterUpdate:Bool = false, appMetaData:String? = nil) {
    
            let deviceUUID = PerfectLib.UUID().string
        let masterVersion:Int64 = 0
        let (uploadRequest, fileSize) = uploadTextFile(deviceUUID:deviceUUID, masterVersion:masterVersion, cloudFolderName: self.testFolder, appMetaData:appMetaData)
        self.sendDoneUploads(expectedNumberOfUploads: 1, deviceUUID:deviceUUID, masterVersion: masterVersion)
        
        self.performServerTest { expectation, googleCreds in
            let headers = self.setupHeaders(accessToken: googleCreds.accessToken)
            
            let downloadFileRequest = DownloadFileRequest(json: [
                DownloadFileRequest.deviceUUIDKey: deviceUUID,
                DownloadFileRequest.fileUUIDKey: uploadRequest.fileUUID,
                DownloadFileRequest.masterVersionKey : "\(masterVersionExpectedWithDownload)",
                DownloadFileRequest.fileVersionKey : uploadRequest.fileVersion,
                DownloadFileRequest.cloudFolderNameKey : self.testFolder
            ])
            
            self.performRequest(route: ServerEndpoints.downloadFile, responseDictFrom:.header, headers: headers, urlParameters: "?" + downloadFileRequest!.urlParameters()!, body:nil) { response, dict in
                Log.info("Status code: \(response!.statusCode)")
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
    
    // TODO: *0* Attempt to download version 1 when you uploaded version 0.
}

