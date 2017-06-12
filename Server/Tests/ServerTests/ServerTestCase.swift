//
//  ServerTestCase.swift
//  Server
//
//  Created by Christopher Prince on 1/7/17.
//
//

// Base XCTestCase class- has no specific tests.

import Foundation
import XCTest
@testable import Server
import LoggerAPI
import PerfectLib

class ServerTestCase : XCTestCase {
    var db:Database!
    
    // A cloud folder name
    let testFolder = "Test.Folder"
    
    override func setUp() {
        super.setUp()
#if os(macOS)
        Constants.delegate = self
        Constants.setup(configFileName: "ServerTests.json")
#else // Linux
        Constants.setup(configFileFullPath: "../../Private/Server/ServerTests.json")
#endif
        self.db = Database()
        
        _ = UserRepository(db).remove()
        _ = UserRepository(db).upcreate()
        _ = UploadRepository(db).remove()
        _ = UploadRepository(db).upcreate()
        _ = MasterVersionRepository(db).remove()
        _ = MasterVersionRepository(db).upcreate()
        _ = FileIndexRepository(db).remove()
        _ = FileIndexRepository(db).upcreate()
        _ = LockRepository(db).remove()
        _ = LockRepository(db).upcreate()
        _ = DeviceUUIDRepository(db).remove()
        _ = DeviceUUIDRepository(db).upcreate()
        _ = SharingInvitationRepository(db).remove()
        _ = SharingInvitationRepository(db).upcreate()
    }
    
    override func tearDown() {
        super.tearDown()
        
        // Otherwise we can have too many db connections open during testing.
        self.db.close()
    }
    
    func addNewUser(token:CredentialsToken = .googleRefreshToken1, deviceUUID:String) {
        self.performServerTest(token:token) { expectation, googleCreds in
            let headers = self.setupHeaders(accessToken: googleCreds.accessToken, deviceUUID:deviceUUID)
            self.performRequest(route: ServerEndpoints.addUser, headers: headers) { response, dict in
                Log.info("Status code: \(response!.statusCode)")
                XCTAssert(response!.statusCode == .OK, "Did not work on addUser request: \(response!.statusCode)")
                expectation.fulfill()
            }
        }
    }
    
    func uploadTextFile(token:CredentialsToken = .googleRefreshToken1, deviceUUID:String = PerfectLib.UUID().string, fileUUID:String? = nil, addUser:Bool=true, updatedMasterVersionExpected:Int64? = nil, fileVersion:FileVersionInt = 0, masterVersion:Int64 = 0, cloudFolderName:String = "CloudFolder", appMetaData:String? = nil, errorExpected:Bool = false) -> (request: UploadFileRequest, fileSize:Int64) {
        if addUser {
            self.addNewUser(deviceUUID:deviceUUID)
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
            UploadFileRequest.fileVersionKey: fileVersion,
            UploadFileRequest.masterVersionKey: masterVersion,
            UploadFileRequest.creationDateKey: DateExtras.date(Date(), toFormat: .DATETIME),
            UploadFileRequest.updateDateKey: DateExtras.date(Date(), toFormat: .DATETIME)
        ])!
        
        uploadRequest.appMetaData = appMetaData
        
        Log.info("Starting runUploadTest: uploadTextFile")
        runUploadTest(token:token, data:data!, uploadRequest:uploadRequest, expectedUploadSize:Int64(stringToUpload.characters.count), updatedMasterVersionExpected:updatedMasterVersionExpected, deviceUUID:deviceUUID, errorExpected: errorExpected)
        Log.info("Completed runUploadTest: uploadTextFile")
        return (request:uploadRequest, fileSize: Int64(stringToUpload.characters.count))
    }
    
    func runUploadTest(token:CredentialsToken = .googleRefreshToken1, data:Data, uploadRequest:UploadFileRequest, expectedUploadSize:Int64, updatedMasterVersionExpected:Int64? = nil, deviceUUID:String, errorExpected:Bool = false) {
        self.performServerTest(token:token) { expectation, googleCreds in
            let headers = self.setupHeaders(accessToken: googleCreds.accessToken, deviceUUID:deviceUUID)
            
            // The method for ServerEndpoints.uploadFile really must be a POST to upload the file.
            XCTAssert(ServerEndpoints.uploadFile.method == .post)
            
            self.performRequest(route: ServerEndpoints.uploadFile, headers: headers, urlParameters: "?" + uploadRequest.urlParameters()!, body:data) { response, dict in
                
                Log.info("Status code: \(response!.statusCode)")

                if errorExpected {
                    XCTAssert(response!.statusCode != .OK, "Worked on uploadFile request!")
                }
                else {
                    XCTAssert(response!.statusCode == .OK, "Did not work on uploadFile request: \(response!.statusCode)")
                    XCTAssert(dict != nil)
                    
                    let sizeInBytes = dict![UploadFileResponse.sizeKey]
                    Log.debug("type of sizeInBytes: \(type(of: sizeInBytes))")
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
    
    func uploadJPEGFile(deviceUUID:String = PerfectLib.UUID().string, addUser:Bool=true, fileVersion:FileVersionInt = 0) -> (request: UploadFileRequest, fileSize:Int64) {
    
        if addUser {
            self.addNewUser(deviceUUID:deviceUUID)
        }
        
        let fileURL = URL(fileURLWithPath: "/tmp/Cat.jpg")
        let sizeOfCatFileInBytes:Int64 = 1162662
        let data = try! Data(contentsOf: fileURL)
        let dateString = DateExtras.date(Date(), toFormat: .DATETIME)

        let uploadRequest = UploadFileRequest(json: [
            UploadFileRequest.fileUUIDKey : PerfectLib.UUID().string,
            UploadFileRequest.mimeTypeKey: "image/jpeg",
            UploadFileRequest.cloudFolderNameKey: testFolder,
            UploadFileRequest.fileVersionKey: fileVersion,
            UploadFileRequest.masterVersionKey: MasterVersionInt(0),
            UploadFileRequest.creationDateKey: dateString,
            UploadFileRequest.updateDateKey: dateString
        ])
        
        Log.info("Starting runUploadTest: uploadJPEGFile")
        runUploadTest(data:data, uploadRequest:uploadRequest!, expectedUploadSize:sizeOfCatFileInBytes, deviceUUID:deviceUUID)
        Log.info("Completed runUploadTest: uploadJPEGFile")
        return (uploadRequest!, sizeOfCatFileInBytes)
    }
    
    func sendDoneUploads(token:CredentialsToken = .googleRefreshToken1, expectedNumberOfUploads:Int32?, deviceUUID:String = PerfectLib.UUID().string, updatedMasterVersionExpected:Int64? = nil, masterVersion:Int64 = 0, failureExpected:Bool = false) {
        self.performServerTest(token:token) { expectation, googleCreds in
            let headers = self.setupHeaders(accessToken: googleCreds.accessToken, deviceUUID:deviceUUID)
            
            let doneUploadsRequest = DoneUploadsRequest(json: [
                DoneUploadsRequest.masterVersionKey : "\(masterVersion)"
            ])
            
            self.performRequest(route: ServerEndpoints.doneUploads, headers: headers, urlParameters: "?" + doneUploadsRequest!.urlParameters()!, body:nil) { response, dict in
                Log.info("Status code: \(response!.statusCode)")
                
                if failureExpected {
                    XCTAssert(response!.statusCode != .OK, "Worked on doneUploadsRequest request!")
                }
                else {
                    XCTAssert(response!.statusCode == .OK, "Did not work on doneUploadsRequest request")
                    XCTAssert(dict != nil)
                    
                    if let doneUploadsResponse = DoneUploadsResponse(json: dict!) {
                        XCTAssert(doneUploadsResponse.masterVersionUpdate == updatedMasterVersionExpected)
                        XCTAssert(doneUploadsResponse.numberUploadsTransferred == expectedNumberOfUploads, "doneUploadsResponse.numberUploadsTransferred: \(String(describing: doneUploadsResponse.numberUploadsTransferred)); expectedNumberOfUploads: \(String(describing: expectedNumberOfUploads))")
                        XCTAssert(doneUploadsResponse.numberDeletionErrors == nil)
                    }
                    else {
                        XCTFail()
                    }
                }
                
                expectation.fulfill()
            }
        }
    }
    
    func getFileIndex(expectedFiles:[UploadFileRequest], deviceUUID:String = PerfectLib.UUID().string, masterVersionExpected:Int64, expectedFileSizes: [String: Int64], expectedDeletionState:[String: Bool]? = nil) {
    
        XCTAssert(expectedFiles.count == expectedFileSizes.count)
        
        self.performServerTest { expectation, googleCreds in
            let headers = self.setupHeaders(accessToken: googleCreds.accessToken, deviceUUID:deviceUUID)
            
            self.performRequest(route: ServerEndpoints.fileIndex, headers: headers, body:nil) { response, dict in
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
                        
                        if expectedDeletionState == nil {
                            XCTAssert(fileInfo.deleted == false)
                        }
                        else {
                            XCTAssert(fileInfo.deleted == expectedDeletionState![fileInfo.fileUUID])
                        }
                        
                        XCTAssert(expectedFile.cloudFolderName == fileInfo.cloudFolderName)
                        
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
    
    func getUploads(expectedFiles:[UploadFileRequest], deviceUUID:String = PerfectLib.UUID().string,expectedFileSizes: [String: Int64]? = nil, matchOptionals:Bool = true, expectedDeletionState:[String: Bool]? = nil) {
    
        if expectedFileSizes != nil {
            XCTAssert(expectedFiles.count == expectedFileSizes!.count)
        }
        
        self.performServerTest { expectation, googleCreds in
            let headers = self.setupHeaders(accessToken: googleCreds.accessToken, deviceUUID:deviceUUID)
            
            self.performRequest(route: ServerEndpoints.getUploads, headers: headers, body:nil) { response, dict in
                Log.info("Status code: \(response!.statusCode)")
                XCTAssert(response!.statusCode == .OK, "Did not work on getUploadsRequest request")
                XCTAssert(dict != nil)
                
                if let getUploadsResponse = GetUploadsResponse(json: dict!) {
                    if getUploadsResponse.uploads == nil {
                        XCTAssert(expectedFiles.count == 0)
                        if expectedFileSizes != nil {
                            XCTAssert(expectedFileSizes!.count == 0)
                        }
                    }
                    else {
                        XCTAssert(getUploadsResponse.uploads!.count == expectedFiles.count)
                        
                        _ = getUploadsResponse.uploads!.map { fileInfo in
                            Log.info("fileInfo: \(fileInfo)")
                            
                            let filterResult = expectedFiles.filter { requestMessage in
                                requestMessage.fileUUID == fileInfo.fileUUID
                            }
                            
                            XCTAssert(filterResult.count == 1)
                            let expectedFile = filterResult[0]
                            
                            XCTAssert(expectedFile.fileUUID == fileInfo.fileUUID)
                            XCTAssert(expectedFile.fileVersion == fileInfo.fileVersion)
                            
                            if matchOptionals {
                                XCTAssert(expectedFile.mimeType == fileInfo.mimeType)
                                XCTAssert(expectedFile.appMetaData == fileInfo.appMetaData)
                                
                                if expectedFileSizes != nil {
                                    XCTAssert(expectedFileSizes![fileInfo.fileUUID] == fileInfo.fileSizeBytes)
                                }
                                
                                XCTAssert(expectedFile.cloudFolderName == fileInfo.cloudFolderName)
                            }
                            
                            if expectedDeletionState == nil {
                                XCTAssert(fileInfo.deleted == false)
                            }
                            else {
                                XCTAssert(fileInfo.deleted == expectedDeletionState![fileInfo.fileUUID])
                            }
                        }
                    }
                }
                else {
                    XCTFail()
                }
                
                expectation.fulfill()
            }
        }
    }

    func createSharingInvitation(token:CredentialsToken = .googleRefreshToken1, permission: SharingPermission? = nil, deviceUUID:String = PerfectLib.UUID().string, errorExpected: Bool = false, completion:@escaping (_ expectation: XCTestExpectation, _ sharingInvitationUUID:String?)->()) {
        self.performServerTest(token:token) { expectation, googleCreds in
            let headers = self.setupHeaders(accessToken: googleCreds.accessToken, deviceUUID:deviceUUID)
            
            var request:CreateSharingInvitationRequest!
            if permission == nil {
                request = CreateSharingInvitationRequest(json: [:])
            }
            else {
                request = CreateSharingInvitationRequest(json: [
                    CreateSharingInvitationRequest.sharingPermissionKey : permission!
                ])
            }
            
            self.performRequest(route: ServerEndpoints.createSharingInvitation, headers: headers, urlParameters: "?" + request!.urlParameters()!, body:nil) { response, dict in
                Log.info("Status code: \(response!.statusCode)")
                if errorExpected {
                    XCTAssert(response!.statusCode != .OK)
                    completion(expectation, nil)
                }
                else {
                    XCTAssert(response!.statusCode == .OK, "Did not work on request: \(response!.statusCode)")
                    XCTAssert(dict != nil)
                    let response = CreateSharingInvitationResponse(json: dict!)
                    completion(expectation, response?.sharingInvitationUUID)
                }
            }
        }
    }
    
    // The sharing user will be that with googleRefreshToken2
    // This also creates the owning user.
    func createSharingUser(withSharingPermission permission:SharingPermission = .read, completion:((_ newUserId:UserId)->())? = nil) {
        // a) Create sharing invitation with one Google account.
        // b) Next, need to "sign out" of that account, and sign into another Google account
        // c) And, redeem sharing invitation with that new Google account.

        // Create the owning user.
        let deviceUUID = PerfectLib.UUID().string
        self.addNewUser(deviceUUID:deviceUUID)
        
        var sharingInvitationUUID:String!
        
        createSharingInvitation(permission: permission) { expectation, invitationUUID in
            sharingInvitationUUID = invitationUUID
            expectation.fulfill()
        }
        
        redeemSharingInvitation(token: .googleRefreshToken2, sharingInvitationUUID: sharingInvitationUUID) { expectation in
            expectation.fulfill()
        }

        // Check to make sure we have a new user:
        let googleSub2 = credentialsToken(token: .googleSub2)
        let userKey = UserRepository.LookupKey.accountTypeInfo(accountType: .Google, credsId: googleSub2)
        let userResults = UserRepository(self.db).lookup(key: userKey, modelInit: User.init)
        guard case .found(let model) = userResults else {
            XCTFail()
            return
        }

        completion?((model as! User).userId)
        
        let key = SharingInvitationRepository.LookupKey.sharingInvitationUUID(uuid: sharingInvitationUUID)
        let results = SharingInvitationRepository(self.db).lookup(key: key, modelInit: SharingInvitation.init)
        
        guard case .noObjectFound = results else {
            XCTFail()
            return
        }
    }
    
    func redeemSharingInvitation(token:CredentialsToken, deviceUUID:String = PerfectLib.UUID().string, sharingInvitationUUID:String? = nil, errorExpected:Bool=false, completion:@escaping (_ expectation: XCTestExpectation)->()) {

        self.performServerTest(token: token) { expectation, googleCreds in
            let headers = self.setupHeaders(accessToken: googleCreds.accessToken, deviceUUID:deviceUUID)
            
            var urlParameters:String?
            
            if sharingInvitationUUID != nil {
                let request = RedeemSharingInvitationRequest(json: [
                    RedeemSharingInvitationRequest.sharingInvitationUUIDKey : sharingInvitationUUID!
                ])
                urlParameters = "?" + request!.urlParameters()!
            }
            
            self.performRequest(route: ServerEndpoints.redeemSharingInvitation, headers: headers, urlParameters: urlParameters, body:nil) { response, dict in
                Log.info("Status code: \(response!.statusCode)")

                if errorExpected {
                    XCTAssert(response!.statusCode != .OK, "Worked on request!")
                }
                else {
                    XCTAssert(response!.statusCode == .OK, "Did not work on request")
                    XCTAssert(dict != nil)
                }
                
                completion(expectation)
            }
        }
    }
    
    func uploadDeletion(token:CredentialsToken = .googleRefreshToken1, uploadDeletionRequest:UploadDeletionRequest, deviceUUID:String, addUser:Bool=true, updatedMasterVersionExpected:Int64? = nil, expectError:Bool = false) {
        if addUser {
            self.addNewUser(deviceUUID:deviceUUID)
        }

        self.performServerTest(token:token) { expectation, googleCreds in
            let headers = self.setupHeaders(accessToken: googleCreds.accessToken, deviceUUID:deviceUUID)
            
            self.performRequest(route: ServerEndpoints.uploadDeletion, headers: headers, urlParameters: "?" + uploadDeletionRequest.urlParameters()!) { response, dict in
                Log.info("Status code: \(response!.statusCode)")
                if expectError {
                    XCTAssert(response!.statusCode != .OK, "Did not fail on upload deletion request")
                }
                else {
                    XCTAssert(response!.statusCode == .OK, "Did not work on upload deletion request")
                    XCTAssert(dict != nil)
                    
                    if let uploadDeletionResponse = UploadDeletionResponse(json: dict!) {
                        if updatedMasterVersionExpected != nil {
                            XCTAssert(uploadDeletionResponse.masterVersionUpdate == updatedMasterVersionExpected)
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
    
    func downloadTextFile(token:CredentialsToken = .googleRefreshToken1,masterVersionExpectedWithDownload:Int, expectUpdatedMasterUpdate:Bool = false, appMetaData:String? = nil, uploadFileVersion:FileVersionInt = 0, downloadFileVersion:FileVersionInt = 0, uploadFileRequest:UploadFileRequest? = nil, fileSize:Int64? = nil, expectedError: Bool = false) {
    
        let deviceUUID = PerfectLib.UUID().string
        let masterVersion:Int64 = 0
        
        var actualUploadFileRequest:UploadFileRequest!
        var actualFileSize:Int64!
        
        if uploadFileRequest == nil {
            let (uploadRequest, size) = uploadTextFile(deviceUUID:deviceUUID, fileVersion:uploadFileVersion, masterVersion:masterVersion, cloudFolderName: self.testFolder, appMetaData:appMetaData)
            actualUploadFileRequest = uploadRequest
            actualFileSize = size
            self.sendDoneUploads(expectedNumberOfUploads: 1, deviceUUID:deviceUUID, masterVersion: masterVersion)
        }
        else {
            actualUploadFileRequest = uploadFileRequest
            actualFileSize = fileSize
        }
        
        self.performServerTest(token:token) { expectation, googleCreds in
            let headers = self.setupHeaders(accessToken: googleCreds.accessToken, deviceUUID:deviceUUID)
            
            let downloadFileRequest = DownloadFileRequest(json: [
                DownloadFileRequest.fileUUIDKey: actualUploadFileRequest!.fileUUID,
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
                            XCTAssert(downloadFileResponse.fileSizeBytes == actualFileSize)
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
}

extension ServerTestCase : ConstantsDelegate {
    // A hack to get access to Server.json during testing.
    public func configFilePath(forConstants:Constants) -> String {
        return "/tmp"
    }
}

