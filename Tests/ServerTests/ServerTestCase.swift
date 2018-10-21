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
import SyncServerShared
import HeliumLogger
import Kitura

#if os(Linux)
    import Glibc
#else
    import Darwin.C
#endif

protocol LinuxTestable {
    associatedtype TestClassType
    static var allTests : [(String, (TestClassType) -> () throws -> Void)] {get}
}

extension LinuxTestable {
    typealias LinuxTestableType = XCTestCase & LinuxTestable
    // Modified from https://oleb.net/blog/2017/03/keeping-xctest-in-sync/
    func linuxTestSuiteIncludesAllTests<T: LinuxTestableType>(testType:T.Type) {
        #if os(macOS) || os(iOS) || os(tvOS) || os(watchOS)
            // Adding 1 to linuxCount because it doesn't have *this* test.
            let linuxCount = testType.allTests.count + 1
        
            let darwinCount = Int(testType.defaultTestSuite.testCaseCount)
            XCTAssertEqual(linuxCount, darwinCount,
                "\(darwinCount - linuxCount) test(s) are missing from allTests")
        #endif
    }
}

class ServerTestCase : XCTestCase {
    var db:Database!
    
    override func setUp() {
        super.setUp()
#if os(macOS)
        Constants.delegate = self
        try! Constants.setup(configFileName: "ServerTests.json")
#else // Linux
        try! Constants.setup(configFileFullPath: "./ServerTests.json")
#endif
        
        Database.remove()
        _ = Database.setup()
        
        self.db = Database()
        
        Log.logger = HeliumLogger()
        HeliumLogger.use(.debug)
    }
    
    override func tearDown() {
        super.tearDown()
        
        // Otherwise we can have too many db connections open during testing.
        self.db.close()
    }
    
    @discardableResult
    func checkOwingUserIdForSharingGroupUser(sharingGroupUUID: String, userId: UserId, sharingUser:TestAccount) -> Bool {
        let key = SharingGroupUserRepository.LookupKey.primaryKeys(sharingGroupUUID: sharingGroupUUID, userId: userId)
        let result = SharingGroupUserRepository(db).lookup(key: key, modelInit: SharingGroupUser.init)
        var sharingGroupUser: Server.SharingGroupUser!
        switch result {
        case .found(let model):
            sharingGroupUser = model as! Server.SharingGroupUser
        case .error, .noObjectFound:
            XCTFail()
            return false
        }
        
        if sharingUser.type.userType == .owning {
            XCTAssert(sharingGroupUser.owningUserId == nil)
            return sharingGroupUser.owningUserId == nil
        }
        else {
            XCTAssert(sharingGroupUser.owningUserId != nil)
            return sharingGroupUser.owningUserId != nil
        }
    }
    
    // The second sharing account joined is returned as the sharingGroupUUID
    @discardableResult
    func redeemWithAnExistingOtherSharingAccount() -> (TestAccount, sharingGroupUUID: String)? {
        var returnResult: (TestAccount, String)?
        
        let deviceUUID = Foundation.UUID().uuidString
        let sharingGroupUUID = Foundation.UUID().uuidString

        guard let _ = self.addNewUser(sharingGroupUUID: sharingGroupUUID, deviceUUID:deviceUUID) else {
            XCTFail()
            return nil
        }
        
        var sharingInvitationUUID:String!
        
        createSharingInvitation(permission: .read, sharingGroupUUID:sharingGroupUUID) { expectation, invitationUUID in
            sharingInvitationUUID = invitationUUID
            expectation.fulfill()
        }
        
        let sharingUser: TestAccount = .primarySharingAccount
        redeemSharingInvitation(sharingUser: sharingUser, sharingInvitationUUID: sharingInvitationUUID) { _, expectation in
            expectation.fulfill()
        }
        
        // Primary sharing account user now exists.

        let sharingGroupUUID2 = Foundation.UUID().uuidString

        // Create a second sharing group and invite/redeem the primary sharing account user.
        guard createSharingGroup(sharingGroupUUID: sharingGroupUUID2, deviceUUID:deviceUUID) else {
            XCTFail()
            return nil
        }
        
        createSharingInvitation(permission: .write, sharingGroupUUID:sharingGroupUUID2) { expectation, invitationUUID in
            sharingInvitationUUID = invitationUUID
            expectation.fulfill()
        }
        
        var result: RedeemSharingInvitationResponse!
        redeemSharingInvitation(sharingUser: sharingUser, sharingInvitationUUID: sharingInvitationUUID) { response, expectation in
            result = response
            expectation.fulfill()
        }
        
        guard result != nil else {
            XCTFail()
            return nil
        }
        
        if checkOwingUserIdForSharingGroupUser(sharingGroupUUID: sharingGroupUUID2, userId: result.userId, sharingUser: sharingUser) {
            returnResult = (sharingUser, sharingGroupUUID2)
        }
        
        return returnResult
    }
    
    @discardableResult
    func uploadAppMetaDataVersion(testAccount:TestAccount = .primaryOwningAccount, deviceUUID: String, fileUUID: String, masterVersion:Int64, appMetaData: AppMetaData, sharingGroupUUID: String, expectedError: Bool = false) -> UploadAppMetaDataResponse? {

        var result:UploadAppMetaDataResponse?
        
        self.performServerTest(testAccount:testAccount) { expectation, testCreds in
            let headers = self.setupHeaders(testUser:testAccount, accessToken: testCreds.accessToken, deviceUUID:deviceUUID)

            let uploadAppMetaDataRequest = UploadAppMetaDataRequest()
            uploadAppMetaDataRequest.fileUUID = fileUUID
            uploadAppMetaDataRequest.masterVersion = masterVersion
            uploadAppMetaDataRequest.appMetaData = appMetaData
            uploadAppMetaDataRequest.sharingGroupUUID = sharingGroupUUID
            
            self.performRequest(route: ServerEndpoints.uploadAppMetaData, headers: headers, urlParameters: "?" + uploadAppMetaDataRequest.urlParameters()!, body:nil) { response, dict in
                Log.info("Status code: \(response!.statusCode)")
                
                if expectedError {
                    XCTAssert(response!.statusCode != .OK, "Did not work on failing uploadAppMetaDataRequest request")
                }
                else {
                    XCTAssert(response!.statusCode == .OK, "Did not work on uploadAppMetaDataRequest request")
                    
                    if let dict = dict,
                        let uploadAppMetaDataResponse = UploadAppMetaDataResponse(json: dict) {
                        if uploadAppMetaDataResponse.masterVersionUpdate == nil {
                            result = uploadAppMetaDataResponse
                        }
                        else {
                            XCTFail()
                        }
                    }
                    else {
                        XCTFail()
                    }
                }
                
                expectation.fulfill()
            }
        }
        
        return result
    }
    
    @discardableResult
    func downloadAppMetaDataVersion(testAccount:TestAccount = .primaryOwningAccount, deviceUUID: String, fileUUID: String, masterVersionExpectedWithDownload:Int64, expectUpdatedMasterUpdate:Bool = false, appMetaDataVersion: AppMetaDataVersionInt? = nil, sharingGroupUUID: String, expectedError: Bool = false) -> DownloadAppMetaDataResponse? {

        var result:DownloadAppMetaDataResponse?
        
        self.performServerTest(testAccount:testAccount) { expectation, testCreds in
            let headers = self.setupHeaders(testUser:testAccount, accessToken: testCreds.accessToken, deviceUUID:deviceUUID)

            let downloadAppMetaDataRequest = DownloadAppMetaDataRequest(json: [
                DownloadAppMetaDataRequest.fileUUIDKey: fileUUID,
                DownloadAppMetaDataRequest.masterVersionKey : "\(masterVersionExpectedWithDownload)",
                DownloadAppMetaDataRequest.appMetaDataVersionKey: appMetaDataVersion as Any,
                ServerEndpoint.sharingGroupUUIDKey: sharingGroupUUID
            ])
            
            if downloadAppMetaDataRequest == nil {
                if !expectedError {
                    XCTFail()
                }
                expectation.fulfill()
                return
            }
            
            self.performRequest(route: ServerEndpoints.downloadAppMetaData, headers: headers, urlParameters: "?" + downloadAppMetaDataRequest!.urlParameters()!, body:nil) { response, dict in
                Log.info("Status code: \(response!.statusCode)")
                
                if expectedError {
                    XCTAssert(response!.statusCode != .OK, "Did not work on failing downloadAppMetaDataRequest request")
                }
                else {
                    XCTAssert(response!.statusCode == .OK, "Did not work on downloadAppMetaDataRequest request")
                    
                    if let dict = dict,
                        let downloadAppMetaDataResponse = DownloadAppMetaDataResponse(json: dict) {
                        result = downloadAppMetaDataResponse
                        if expectUpdatedMasterUpdate {
                            XCTAssert(downloadAppMetaDataResponse.masterVersionUpdate != nil)
                        }
                        else {
                            XCTAssert(downloadAppMetaDataResponse.masterVersionUpdate == nil)
                        }
                    }
                    else {
                        XCTFail()
                    }
                }
                
                expectation.fulfill()
            }
        }
        
        return result
    }
    
    @discardableResult
    func healthCheck() -> HealthCheckResponse? {
        var result:HealthCheckResponse?
        
        performServerTest { expectation, creds in
            self.performRequest(route: ServerEndpoints.healthCheck) { response, dict in
                XCTAssert(response!.statusCode == .OK, "Failed on healthcheck request")
                
                guard let dict = dict, let healthCheckResponse = HealthCheckResponse(json: dict) else {
                    XCTFail()
                    return
                }
                
                XCTAssert(healthCheckResponse.serverUptime > 0)
                XCTAssert(healthCheckResponse.deployedGitTag.count > 0)
                XCTAssert(healthCheckResponse.currentServerDateTime != nil)
    
                result = healthCheckResponse
                expectation.fulfill()
            }
        }
        
        return result
    }
    
    private func deleteFile(testAccount: TestAccount, cloudFileName: String, options: CloudStorageFileNameOptions) {
        
        let expectation = self.expectation(description: "expectation")

        switch testAccount.type {
        case .Google:
            let creds = GoogleCreds()
            creds.refreshToken = testAccount.token()
            creds.refresh { error in
                guard error == nil, creds.accessToken != nil else {
                    print("Error: \(error!)")
                    XCTFail()
                    expectation.fulfill()
                    return
                }
                
                creds.deleteFile(cloudFileName:cloudFileName, options:options) { error in
                    expectation.fulfill()
                }
            }
            
        case .Dropbox:
            let creds = DropboxCreds()
            creds.accessToken = testAccount.token()
            creds.accountId = testAccount.id()
            creds.deleteFile(cloudFileName:cloudFileName, options:options) { error in
                expectation.fulfill()
            }
            
        default:
            assert(false)
        }
        
        waitForExpectations(timeout: 10.0, handler: nil)
    }
    
    enum LookupFileError : Error {
    case errorOrNoAccessToken
    }
    
    @discardableResult
    func lookupFile(forOwningTestAccount testAccount: TestAccount, cloudFileName: String, options: CloudStorageFileNameOptions) -> Bool? {
    
        var lookupResult: Bool?
        
        let expectation = self.expectation(description: "expectation")
    
        switch testAccount.type {
        case .Google:
            let creds = GoogleCreds()
            creds.refreshToken = testAccount.token()
            creds.refresh { error in
                guard error == nil, creds.accessToken != nil else {
                    XCTFail()
                    expectation.fulfill()
                    return
                }
            
                creds.lookupFile(cloudFileName:cloudFileName, options:options) { result in
                    switch result {
                    case .success (let found):
                        lookupResult = found
                    case .failure:
                        XCTFail()
                    }
                    
                    expectation.fulfill()
                }
            }
            
        case .Dropbox:
            let creds = DropboxCreds()
            creds.accessToken = testAccount.token()
            creds.accountId = testAccount.id()
            
            creds.lookupFile(cloudFileName:cloudFileName, options:options) { result in
                switch result {
                case .success (let found):
                    lookupResult = found
                case .failure:
                    XCTFail()
                }
                
                expectation.fulfill()
            }
            
        default:
            assert(false)
        }
        
        waitForExpectations(timeout: 10.0, handler: nil)
        
        return lookupResult
    }
    
    @discardableResult
    func addNewUser(testAccount:TestAccount = .primaryOwningAccount, sharingGroupUUID: String, deviceUUID:String, cloudFolderName: String? = ServerTestCase.cloudFolderName, sharingGroupName:String? = nil) -> AddUserResponse? {
        var result:AddUserResponse?

        if let fileName = Constants.session.owningUserAccountCreation.initialFileName {
            // Need to delete the initialization file in the test account, so that if we're creating the user test account for a 2nd, 3rd etc time, we don't fail.
            let options = CloudStorageFileNameOptions(cloudFolderName: cloudFolderName, mimeType: "text/plain")
            
            deleteFile(testAccount: testAccount, cloudFileName: fileName, options: options)
            result = addNewUser2(testAccount:testAccount, sharingGroupUUID: sharingGroupUUID, deviceUUID:deviceUUID, cloudFolderName: cloudFolderName, sharingGroupName: sharingGroupName)
        }
        else {
            result = addNewUser2(testAccount:testAccount, sharingGroupUUID: sharingGroupUUID, deviceUUID:deviceUUID, cloudFolderName: cloudFolderName, sharingGroupName: sharingGroupName)
        }
        
        return result
    }
    
    private func addNewUser2(testAccount:TestAccount, sharingGroupUUID: String, deviceUUID:String, cloudFolderName: String?, sharingGroupName:String?) -> AddUserResponse? {
        var result:AddUserResponse?
        
        let addUserRequest = AddUserRequest(json: [
            AddUserRequest.cloudFolderNameKey : cloudFolderName as Any,
            AddUserRequest.sharingGroupNameKey: sharingGroupName as Any,
            ServerEndpoint.sharingGroupUUIDKey: sharingGroupUUID
        ])!
        
        self.performServerTest(testAccount:testAccount) { expectation, creds in
            let headers = self.setupHeaders(testUser: testAccount, accessToken: creds.accessToken, deviceUUID:deviceUUID)
            
            var queryParams:String?
            if let params = addUserRequest.urlParameters() {
                queryParams = "?" + params
            }
            
            self.performRequest(route: ServerEndpoints.addUser, headers: headers, urlParameters: queryParams) { response, dict in
                Log.info("Status code: \(response!.statusCode)")
                XCTAssert(response!.statusCode == .OK, "Did not work on addUser request: \(response!.statusCode)")
                
                if let dict = dict, let addUserResponse = AddUserResponse(json: dict) {
                    XCTAssert(addUserResponse.userId != nil)
                    result = addUserResponse
                }
                else {
                    XCTFail()
                }

                expectation.fulfill()
            }
        }
        
        return result
    }
    
    @discardableResult
    // Returns sharing group UUID
    func createSharingGroup(testAccount:TestAccount = .primaryOwningAccount, sharingGroupUUID:String, deviceUUID:String, sharingGroup: SyncServerShared.SharingGroup? = nil, errorExpected: Bool = false) -> Bool {
        var result: Bool = false
        
        let createRequest = CreateSharingGroupRequest(json: [
            CreateSharingGroupRequest.sharingGroupNameKey: sharingGroup?.sharingGroupName as Any,
            ServerEndpoint.sharingGroupUUIDKey: sharingGroupUUID
        ])!
        
        self.performServerTest(testAccount:testAccount) { expectation, creds in
            let headers = self.setupHeaders(testUser: testAccount, accessToken: creds.accessToken, deviceUUID:deviceUUID)
            
            var queryParams:String?
            if let params = createRequest.urlParameters() {
                queryParams = "?" + params
            }
            
            self.performRequest(route: ServerEndpoints.createSharingGroup, headers: headers, urlParameters: queryParams) { response, dict in
                Log.info("Status code: \(response!.statusCode)")
                if errorExpected {
                    XCTAssert(response!.statusCode != .OK)
                }
                else {
                    XCTAssert(response!.statusCode == .OK, "Did not work on create sharing group request: \(response!.statusCode)")
                }
                
                if !errorExpected {
                    if let dict = dict, let _ = CreateSharingGroupResponse(json: dict) {
                        result = true
                    }
                    else {
                        XCTFail()
                    }
                }
                
                expectation.fulfill()
            }
        }
        
        return result
    }
    
    @discardableResult
    func updateSharingGroup(testAccount:TestAccount = .primaryOwningAccount, deviceUUID:String, sharingGroup: SyncServerShared.SharingGroup, masterVersion: MasterVersionInt, expectMasterVersionUpdate: Bool = false, expectFailure: Bool = false) -> Bool {
        var result: Bool = false
        
        let updateRequest = UpdateSharingGroupRequest(json: [
            ServerEndpoint.sharingGroupUUIDKey: sharingGroup.sharingGroupUUID as Any,
            UpdateSharingGroupRequest.sharingGroupNameKey: sharingGroup.sharingGroupName as Any,
            ServerEndpoint.masterVersionKey: masterVersion
        ])!
        
        self.performServerTest(testAccount:testAccount) { expectation, creds in
            let headers = self.setupHeaders(testUser: testAccount, accessToken: creds.accessToken, deviceUUID:deviceUUID)
            
            var queryParams:String?
            if let params = updateRequest.urlParameters() {
                queryParams = "?" + params
            }
            
            self.performRequest(route: ServerEndpoints.updateSharingGroup, headers: headers, urlParameters: queryParams) { response, dict in
                Log.info("Status code: \(response!.statusCode)")
                
                if expectFailure {
                    XCTAssert(response!.statusCode != .OK)
                }
                else {
                    XCTAssert(response!.statusCode == .OK, "Did not work on update sharing group request: \(response!.statusCode)")
                    
                    if let dict = dict, let response = UpdateSharingGroupResponse(json: dict) {
                        if let _ = response.masterVersionUpdate {
                            XCTAssert(expectMasterVersionUpdate)
                        }
                        else {
                            XCTAssert(!expectMasterVersionUpdate)
                        }
                        
                        result = true
                    }
                    else {
                        XCTFail()
                    }
                }
                
                expectation.fulfill()
            }
        }
        
        return result
    }
    
    @discardableResult
    func removeSharingGroup(testAccount:TestAccount = .primaryOwningAccount, deviceUUID:String, sharingGroupUUID: String, masterVersion: MasterVersionInt) -> Bool {
        var result: Bool = false
        
        let removeRequest = RemoveSharingGroupRequest(json: [
            ServerEndpoint.sharingGroupUUIDKey: sharingGroupUUID,
            ServerEndpoint.masterVersionKey: masterVersion
        ])!
        
        self.performServerTest(testAccount:testAccount) { expectation, creds in
            let headers = self.setupHeaders(testUser: testAccount, accessToken: creds.accessToken, deviceUUID:deviceUUID)
            
            var queryParams:String?
            if let params = removeRequest.urlParameters() {
                queryParams = "?" + params
            }
            
            self.performRequest(route: ServerEndpoints.removeSharingGroup, headers: headers, urlParameters: queryParams) { response, dict in
                Log.info("Status code: \(response!.statusCode)")
                XCTAssert(response!.statusCode == .OK, "Did not work on remove sharing group request: \(response!.statusCode)")
                
                if let dict = dict, let response = RemoveSharingGroupResponse(json: dict) {
                    if let _ = response.masterVersionUpdate {
                        result = false
                    }
                    else {
                        result = true
                    }
                }
                else {
                    XCTFail()
                }

                expectation.fulfill()
            }
        }
        
        return result
    }
    
    @discardableResult
    func removeUserFromSharingGroup(testAccount:TestAccount = .primaryOwningAccount, deviceUUID:String, sharingGroupUUID: String, masterVersion: MasterVersionInt, expectMasterVersionUpdate: Bool = false) -> Bool {
        var result: Bool = false
        
        let removeRequest = RemoveUserFromSharingGroupRequest(json: [
            ServerEndpoint.sharingGroupUUIDKey: sharingGroupUUID,
            ServerEndpoint.masterVersionKey: masterVersion
        ])!
        
        self.performServerTest(testAccount:testAccount) { expectation, creds in
            let headers = self.setupHeaders(testUser: testAccount, accessToken: creds.accessToken, deviceUUID:deviceUUID)
            
            var queryParams:String?
            if let params = removeRequest.urlParameters() {
                queryParams = "?" + params
            }
            
            self.performRequest(route: ServerEndpoints.removeUserFromSharingGroup, headers: headers, urlParameters: queryParams) { response, dict in
                Log.info("Status code: \(response!.statusCode)")
                XCTAssert(response!.statusCode == .OK, "Did not work on remove user from sharing group request: \(response!.statusCode)")
                
                if let dict = dict, let response = RemoveUserFromSharingGroupResponse(json: dict) {
                    if let _ = response.masterVersionUpdate {
                        XCTAssert(expectMasterVersionUpdate)
                    }
                    else {
                        XCTAssert(!expectMasterVersionUpdate)
                    }
                    result = true
                }
                else {
                    XCTFail()
                }

                expectation.fulfill()
            }
        }
        
        return result
    }
    
    static let cloudFolderName = "CloudFolder"
    static let uploadTextFileContents = "Hello World!"
    
    struct UploadFileResult {
        let request: UploadFileRequest
        let fileSize:Int64
        let sharingGroupUUID:String?
        let uploadingUserId: UserId?
    }
    
    enum AddUser {
        case no(sharingGroupUUID: String)
        case yes
    }
    
    // statusCodeExpected is only used if an error is expected.
    @discardableResult
    func uploadTextFile(testAccount:TestAccount = .primaryOwningAccount, deviceUUID:String = Foundation.UUID().uuidString, fileUUID:String? = nil, addUser:AddUser = .yes, updatedMasterVersionExpected:Int64? = nil, fileVersion:FileVersionInt = 0, masterVersion:Int64 = 0, cloudFolderName:String? = ServerTestCase.cloudFolderName, appMetaData:AppMetaData? = nil, errorExpected:Bool = false, undelete: Int32 = 0, contents: String? = nil, fileGroupUUID:String? = nil, statusCodeExpected: HTTPStatusCode? = nil) -> UploadFileResult? {
    
        var sharingGroupUUID = UUID().uuidString
        var uploadingUserId: UserId?
        
        switch addUser {
        case .yes:
            guard let addUserResponse = self.addNewUser(testAccount:testAccount, sharingGroupUUID: sharingGroupUUID, deviceUUID:deviceUUID, cloudFolderName: cloudFolderName) else {
                XCTFail()
                return nil
            }

            uploadingUserId = addUserResponse.userId
        case .no(sharingGroupUUID: let id):
            sharingGroupUUID = id
        }
        
        var fileUUIDToSend = ""
        if fileUUID == nil {
            fileUUIDToSend = Foundation.UUID().uuidString
        }
        else {
            fileUUIDToSend = fileUUID!
        }
        
        var data:Data!
        var uploadString = ServerTestCase.uploadTextFileContents
        if let contents = contents {
            data = contents.data(using: .utf8)!
            uploadString = contents
        }
        else {
            data = ServerTestCase.uploadTextFileContents.data(using: .utf8)!
        }
        
        let uploadRequest = UploadFileRequest(json: [
            UploadFileRequest.fileUUIDKey : fileUUIDToSend,
            UploadFileRequest.mimeTypeKey: "text/plain",
            UploadFileRequest.fileVersionKey: fileVersion,
            UploadFileRequest.masterVersionKey: masterVersion,
            UploadFileRequest.undeleteServerFileKey: undelete,
            UploadFileRequest.fileGroupUUIDKey: fileGroupUUID as Any,
            ServerEndpoint.sharingGroupUUIDKey: sharingGroupUUID
        ])!
        
        uploadRequest.appMetaData = appMetaData
        
        Log.info("Starting runUploadTest: uploadTextFile: uploadRequest: \(String(describing: uploadRequest.toJSON()))")
        runUploadTest(testAccount:testAccount, data:data, uploadRequest:uploadRequest, expectedUploadSize:Int64(uploadString.count), updatedMasterVersionExpected:updatedMasterVersionExpected, deviceUUID:deviceUUID, errorExpected: errorExpected, statusCodeExpected: statusCodeExpected)
        Log.info("Completed runUploadTest: uploadTextFile")
        
        return UploadFileResult(request: uploadRequest, fileSize: Int64(uploadString.count), sharingGroupUUID: sharingGroupUUID, uploadingUserId: uploadingUserId)
    }
    
    func runUploadTest(testAccount:TestAccount = .primaryOwningAccount, data:Data, uploadRequest:UploadFileRequest, expectedUploadSize:Int64, updatedMasterVersionExpected:Int64? = nil, deviceUUID:String, errorExpected:Bool = false, statusCodeExpected: HTTPStatusCode? = nil) {
        
        self.performServerTest(testAccount:testAccount) { expectation, testCreds in
            let headers = self.setupHeaders(testUser: testAccount, accessToken: testCreds.accessToken, deviceUUID:deviceUUID)
            
            // The method for ServerEndpoints.uploadFile really must be a POST to upload the file.
            XCTAssert(ServerEndpoints.uploadFile.method == .post)
            
            Log.debug("uploadRequest.urlParameters(): \(uploadRequest.urlParameters()!)")
            
            self.performRequest(route: ServerEndpoints.uploadFile, responseDictFrom: .header, headers: headers, urlParameters: "?" + uploadRequest.urlParameters()!, body:data) { response, dict in
                
                Log.info("Status code: \(response!.statusCode)")

                if errorExpected {
                    if let statusCodeExpected = statusCodeExpected {
                        XCTAssert(response!.statusCode == statusCodeExpected)
                    }
                    else {
                        XCTAssert(response!.statusCode != .OK, "Worked on uploadFile request!")
                    }
                }
                else {
                    guard response!.statusCode == .OK, dict != nil else {
                        XCTFail("Did not work on uploadFile request: \(response!.statusCode)")
                        expectation.fulfill()
                        return
                    }
                    
                    let sizeInBytes = dict![UploadFileResponse.sizeKey]
                    Log.debug("type of sizeInBytes: \(type(of: sizeInBytes))")
                    if let uploadResponse = UploadFileResponse(json: dict!) {
                        if updatedMasterVersionExpected == nil {
                            XCTAssert(uploadResponse.size != nil)
                            XCTAssert(uploadResponse.size == expectedUploadSize)
                            XCTAssert(uploadResponse.creationDate != nil)
                            XCTAssert(uploadResponse.updateDate != nil)
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
    
    static let jpegMimeType = "image/jpeg"
    func uploadJPEGFile(deviceUUID:String = Foundation.UUID().uuidString,
        fileUUID:String = Foundation.UUID().uuidString, addUser:AddUser = .yes, fileVersion:FileVersionInt = 0, expectedMasterVersion:MasterVersionInt = 0, appMetaData:AppMetaData? = nil, errorExpected:Bool = false) -> UploadFileResult? {
    
        var sharingGroupUUID: String!
        var uploadingUserId: UserId?
        
        switch addUser {
        case .yes:
            sharingGroupUUID = UUID().uuidString
            guard let addUserResponse = self.addNewUser(sharingGroupUUID: sharingGroupUUID, deviceUUID:deviceUUID) else {
                XCTFail()
                return nil
            }
            uploadingUserId = addUserResponse.userId
        case .no(sharingGroupUUID: let id):
            sharingGroupUUID = id
        }
        
#if os(macOS)
        let fileURL = URL(fileURLWithPath: "/tmp/Cat.jpg")
#else
        let fileURL = URL(fileURLWithPath: "./Resources/Cat.jpg")
#endif

        let sizeOfCatFileInBytes:Int64 = 1162662
        guard let data = try? Data(contentsOf: fileURL) else {
            XCTFail()
            return nil
        }

        guard let uploadRequest = UploadFileRequest(json: [
            UploadFileRequest.fileUUIDKey : fileUUID,
            UploadFileRequest.mimeTypeKey: ServerTestCase.jpegMimeType,
            UploadFileRequest.fileVersionKey: fileVersion,
            UploadFileRequest.masterVersionKey: expectedMasterVersion,
            ServerEndpoint.sharingGroupUUIDKey: sharingGroupUUID
            ]) else {
            XCTFail()
            return nil
        }
        
        uploadRequest.appMetaData = appMetaData
        
        Log.info("Starting runUploadTest: uploadJPEGFile")
        runUploadTest(data:data, uploadRequest:uploadRequest, expectedUploadSize:sizeOfCatFileInBytes, deviceUUID:deviceUUID, errorExpected: errorExpected)
        Log.info("Completed runUploadTest: uploadJPEGFile")
        return UploadFileResult(request: uploadRequest, fileSize: sizeOfCatFileInBytes, sharingGroupUUID: sharingGroupUUID, uploadingUserId:uploadingUserId)
    }
    
    // sharingGroupName enables you to change the sharing group name during the DoneUploads.
    func sendDoneUploads(testAccount:TestAccount = .primaryOwningAccount, expectedNumberOfUploads:Int32?, deviceUUID:String = Foundation.UUID().uuidString, updatedMasterVersionExpected:Int64? = nil, masterVersion:Int64 = 0, sharingGroupUUID: String, sharingGroupName: String? = nil, failureExpected:Bool = false) {
        
        self.performServerTest(testAccount:testAccount) { expectation, testCreds in
            let headers = self.setupHeaders(testUser: testAccount, accessToken: testCreds.accessToken, deviceUUID:deviceUUID)
            
            let doneUploadsRequest = DoneUploadsRequest(json: [
                ServerEndpoint.masterVersionKey : "\(masterVersion)",
                ServerEndpoint.sharingGroupUUIDKey: sharingGroupUUID
            ])
            
            if let sharingGroupName = sharingGroupName {
                doneUploadsRequest?.sharingGroupName = sharingGroupName
            }
            
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
    
    func getIndex(expectedFiles:[UploadFileRequest]? = nil, deviceUUID:String = Foundation.UUID().uuidString, masterVersionExpected:Int64? = nil, expectedFileSizes: [String: Int64]? = nil, sharingGroupUUID: String? = nil, expectedDeletionState:[String: Bool]? = nil, errorExpected: Bool = false) {
    
        if let expectedFiles = expectedFiles {
            XCTAssert(expectedFiles.count == expectedFileSizes!.count)
        }
        
        let indexRequest = IndexRequest(json: [
            ServerEndpoint.sharingGroupUUIDKey: sharingGroupUUID as Any
        ])
    
        guard let request = indexRequest,
            let parameters = request.urlParameters() else {
            XCTFail()
            return
        }
        
        self.performServerTest { expectation, creds in
            let headers = self.setupHeaders(testUser: .primaryOwningAccount, accessToken: creds.accessToken, deviceUUID:deviceUUID)
            
            self.performRequest(route: ServerEndpoints.index, headers: headers, urlParameters: "?" + parameters, body:nil) { response, dict in
                Log.info("Status code: \(response!.statusCode)")

                if errorExpected {
                    XCTAssert(response!.statusCode != .OK)
                }
                else {
                    XCTAssert(response!.statusCode == .OK, "Did not work on IndexRequest request")
                    XCTAssert(dict != nil)

                    if let indexResponse = IndexResponse(json: dict!) {
                        XCTAssert(indexResponse.masterVersion == masterVersionExpected)
                        if let expectedFiles = expectedFiles {
                            guard let fileIndex = indexResponse.fileIndex else {
                                XCTFail()
                                return
                            }
                            
                            XCTAssert(fileIndex.count == expectedFiles.count)
                            
                            fileIndex.forEach { fileInfo in
                                Log.info("fileInfo: \(fileInfo)")
                                
                                let filterResult = expectedFiles.filter { uploadFileRequest in
                                    uploadFileRequest.fileUUID == fileInfo.fileUUID
                                }
                                
                                XCTAssert(filterResult.count == 1)
                                let expectedFile = filterResult[0]
                                
                                XCTAssert(expectedFile.fileUUID == fileInfo.fileUUID)
                                XCTAssert(expectedFile.fileVersion == fileInfo.fileVersion)
                                XCTAssert(expectedFile.mimeType == fileInfo.mimeType)
                                
                                if expectedDeletionState == nil {
                                    XCTAssert(fileInfo.deleted == false)
                                }
                                else {
                                    XCTAssert(fileInfo.deleted == expectedDeletionState![fileInfo.fileUUID])
                                }
                                
                                XCTAssert(expectedFileSizes?[fileInfo.fileUUID] == fileInfo.fileSizeBytes)
                            }
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
    
    func getIndex(testAccount: TestAccount = .primaryOwningAccount, deviceUUID:String = Foundation.UUID().uuidString, sharingGroupUUID: String? = nil) -> ([FileInfo]?, [SyncServerShared.SharingGroup])? {
        var result:([FileInfo]?, [SyncServerShared.SharingGroup])?
        
        self.performServerTest(testAccount: testAccount) { expectation, creds in
            let headers = self.setupHeaders(testUser: testAccount, accessToken: creds.accessToken, deviceUUID:deviceUUID)
            
            let indexRequest = IndexRequest(json: [
                ServerEndpoint.sharingGroupUUIDKey: sharingGroupUUID as Any
            ])
            
            guard let request = indexRequest else {
                expectation.fulfill()
                XCTFail()
                return
            }
            
            var urlParameters = ""
            if let parameters = request.urlParameters() {
                urlParameters = "?" + parameters
            }
            
            self.performRequest(route: ServerEndpoints.index, headers: headers, urlParameters: urlParameters, body:nil) { response, dict in
                Log.info("Status code: \(response!.statusCode)")
                XCTAssert(response!.statusCode == .OK, "Did not work on IndexRequest")
                XCTAssert(dict != nil)
                
                guard let indexResponse = IndexResponse(json: dict!),
                    let groups = indexResponse.sharingGroups else {
                    expectation.fulfill()
                    XCTFail()
                    return
                }
                
                if sharingGroupUUID == nil {
                    XCTAssert(indexResponse.fileIndex == nil)
                    XCTAssert(indexResponse.masterVersion == nil)
                }
                else {
                    XCTAssert(indexResponse.fileIndex != nil)
                    XCTAssert(indexResponse.masterVersion != nil)
                }
                
                result = (indexResponse.fileIndex, groups)
                expectation.fulfill()
            }
        }
        
        return result
    }
    
    func getMasterVersion(testAccount: TestAccount = .primaryOwningAccount, deviceUUID:String = Foundation.UUID().uuidString, sharingGroupUUID: String) -> MasterVersionInt? {
        var result:MasterVersionInt?
        
        self.performServerTest(testAccount: testAccount) { expectation, creds in
            let headers = self.setupHeaders(testUser: testAccount, accessToken: creds.accessToken, deviceUUID:deviceUUID)
            
            let indexRequest = IndexRequest(json: [
                ServerEndpoint.sharingGroupUUIDKey: sharingGroupUUID as Any
            ])
            
            guard let request = indexRequest else {
                expectation.fulfill()
                XCTFail()
                return
            }
            
            var urlParameters = ""
            if let parameters = request.urlParameters() {
                urlParameters = "?" + parameters
            }
            
            self.performRequest(route: ServerEndpoints.index, headers: headers, urlParameters: urlParameters, body:nil) { response, dict in
                Log.info("Status code: \(response!.statusCode)")
                XCTAssert(response!.statusCode == .OK, "Did not work on IndexRequest")
                XCTAssert(dict != nil)
                
                guard let indexResponse = IndexResponse(json: dict!) else {
                    expectation.fulfill()
                    XCTFail()
                    return
                }
                
                result = indexResponse.masterVersion
                expectation.fulfill()
            }
        }
        
        return result
    }
    
    func getUploads(expectedFiles:[UploadFileRequest], deviceUUID:String = Foundation.UUID().uuidString, expectedFileSizes: [String: Int64]? = nil, matchOptionals:Bool = true, expectedDeletionState:[String: Bool]? = nil, sharingGroupUUID: String, errorExpected: Bool = false) {
    
        if expectedFileSizes != nil {
            XCTAssert(expectedFiles.count == expectedFileSizes!.count)
        }
        
        let getUploadsRequest = GetUploadsRequest(json: [
            ServerEndpoint.sharingGroupUUIDKey: sharingGroupUUID
        ])
        
        guard let request = getUploadsRequest,
            let params = request.urlParameters() else {
            XCTFail()
            return
        }
        
        self.performServerTest { expectation, creds in
            let headers = self.setupHeaders(testUser: .primaryOwningAccount, accessToken: creds.accessToken, deviceUUID:deviceUUID)
            
            self.performRequest(route: ServerEndpoints.getUploads, headers: headers, urlParameters: "?" + params, body:nil) { response, dict in
            
                Log.info("Status code: \(response!.statusCode)")
                if errorExpected {
                    XCTAssert(response!.statusCode != .OK)
                }
                else {
                    XCTAssert(response!.statusCode == .OK, "Did not work on getUploadsRequest request")
                    XCTAssert(dict != nil)
                }
                
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
                                
                                if expectedFileSizes != nil {
                                    XCTAssert(expectedFileSizes![fileInfo.fileUUID] == fileInfo.fileSizeBytes)
                                }
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

    func createSharingInvitation(testAccount: TestAccount = .primaryOwningAccount, permission: Permission? = nil, deviceUUID:String = Foundation.UUID().uuidString, sharingGroupUUID: String, errorExpected: Bool = false, completion:@escaping (_ expectation: XCTestExpectation, _ sharingInvitationUUID:String?)->()) {
        
        self.performServerTest(testAccount: testAccount) { expectation, testCreds in
            let headers = self.setupHeaders(testUser:testAccount, accessToken: testCreds.accessToken, deviceUUID:deviceUUID)
            
            var request:CreateSharingInvitationRequest!
            if permission == nil {
                request = CreateSharingInvitationRequest(json: [
                    ServerEndpoint.sharingGroupUUIDKey: sharingGroupUUID
                ])
            }
            else {
                request = CreateSharingInvitationRequest(json: [
                    CreateSharingInvitationRequest.permissionKey : permission!,
                    ServerEndpoint.sharingGroupUUIDKey: sharingGroupUUID
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
    
    // This also creates the owning user-- using .primaryOwningAccount
    func createSharingUser(withSharingPermission permission:Permission = .read, sharingUser:TestAccount = .google2, addUser:AddUser = .yes, owningUserWhenCreating:TestAccount = .primaryOwningAccount, failureExpected: Bool = false, completion:((_ newSharingUserId:UserId?, _ sharingGroupUUID: String?)->())? = nil) {
        // a) Create sharing invitation with one account.
        // b) Next, need to "sign out" of that account, and sign into another account
        // c) And, redeem sharing invitation with that new account.

        // Create the owning user, if needed.
        let deviceUUID = Foundation.UUID().uuidString
        var actualSharingGroupUUID:String!
        switch addUser {
        case .no(let sharingGroupUUID):
            actualSharingGroupUUID = sharingGroupUUID

        case .yes:
            actualSharingGroupUUID = Foundation.UUID().uuidString
            guard let _ = self.addNewUser(testAccount: owningUserWhenCreating, sharingGroupUUID: actualSharingGroupUUID, deviceUUID:deviceUUID) else {
                XCTFail()
                completion?(nil, nil)
                return
            }
        }

        var sharingInvitationUUID:String!
        
        createSharingInvitation(testAccount: owningUserWhenCreating, permission: permission, sharingGroupUUID:actualSharingGroupUUID) { expectation, invitationUUID in
            sharingInvitationUUID = invitationUUID
            expectation.fulfill()
        }
        
        redeemSharingInvitation(sharingUser:sharingUser, sharingInvitationUUID: sharingInvitationUUID, errorExpected: failureExpected) { result, expectation in
            XCTAssert(result?.userId != nil && result?.sharingGroupUUID != nil)
            expectation.fulfill()
        }

        if failureExpected {
            completion?(nil, nil)
        }
        else {
            // Check to make sure we have a new user:
            let userKey = UserRepository.LookupKey.accountTypeInfo(accountType: sharingUser.type, credsId: sharingUser.id())
            let userResults = UserRepository(self.db).lookup(key: userKey, modelInit: User.init)
            guard case .found(let model) = userResults else {
                Log.debug("sharingUser.type: \(sharingUser.type); sharingUser.id(): \(sharingUser.id())")
                XCTFail()
                completion?(nil, nil)
                return
            }
            
            let key = SharingInvitationRepository.LookupKey.sharingInvitationUUID(uuid: sharingInvitationUUID)
            let results = SharingInvitationRepository(self.db).lookup(key: key, modelInit: SharingInvitation.init)
            
            guard case .noObjectFound = results else {
                XCTFail()
                completion?(nil, nil)
                return
            }
            
            guard let (_, sharingGroups) = getIndex() else {
                XCTFail()
                return
            }
            
            guard sharingGroups.count == 1 else {
                XCTFail()
                return
            }
            
            XCTAssert(sharingGroups[0].sharingGroupUUID == actualSharingGroupUUID)
            XCTAssert(sharingGroups[0].sharingGroupName == nil)
            XCTAssert(sharingGroups[0].deleted == false)
            guard sharingGroups[0].sharingGroupUsers != nil else {
                XCTFail()
                return
            }
            
            guard sharingGroups[0].sharingGroupUsers.count >= 2 else {
                XCTFail()
                return
            }
            
            sharingGroups[0].sharingGroupUsers.forEach { sgu in
                XCTAssert(sgu.name != nil)
                XCTAssert(sgu.userId != nil)
            }
            
            completion?((model as! User).userId, actualSharingGroupUUID)
        }
    }
    
    func redeemSharingInvitation(sharingUser:TestAccount, deviceUUID:String = Foundation.UUID().uuidString, canGiveCloudFolderName: Bool = true, sharingInvitationUUID:String? = nil, errorExpected:Bool=false, completion:@escaping (_ result: RedeemSharingInvitationResponse?, _ expectation: XCTestExpectation)->()) {
    
        var actualCloudFolderName: String?
        if sharingUser.type == .Google && canGiveCloudFolderName {
            actualCloudFolderName = ServerTestCase.cloudFolderName
        }

        self.performServerTest(testAccount:sharingUser) { expectation, accountCreds in
            let headers = self.setupHeaders(testUser: sharingUser, accessToken: accountCreds.accessToken, deviceUUID:deviceUUID)
            
            var urlParameters:String?
            
            if sharingInvitationUUID != nil {
                let request = RedeemSharingInvitationRequest(json: [
                    RedeemSharingInvitationRequest.sharingInvitationUUIDKey : sharingInvitationUUID!,
                    AddUserRequest.cloudFolderNameKey: actualCloudFolderName as Any
                ])
                urlParameters = "?" + request!.urlParameters()!
            }
            
            self.performRequest(route: ServerEndpoints.redeemSharingInvitation, headers: headers, urlParameters: urlParameters, body:nil) { response, dict in
                Log.info("Status code: \(response!.statusCode)")

                var result: RedeemSharingInvitationResponse?
                
                if errorExpected {
                    XCTAssert(response!.statusCode != .OK, "Worked on request!")
                }
                else {
                    XCTAssert(response!.statusCode == .OK, "Did not work on request")
                    
                    if let dict = dict,
                        let redeemSharingInvitationResponse = RedeemSharingInvitationResponse(json: dict) {
                        result = redeemSharingInvitationResponse
                    }
                    else {
                        XCTFail()
                    }
                }
                
                completion(result, expectation)
            }
        }
    }
    
    func uploadDeletion(testAccount:TestAccount = .primaryOwningAccount, uploadDeletionRequest:UploadDeletionRequest, deviceUUID:String, addUser:Bool=true, updatedMasterVersionExpected:Int64? = nil, expectError:Bool = false) {

        if addUser {
            let sharingGroupUUID = UUID().uuidString
            guard let _ = self.addNewUser(sharingGroupUUID: sharingGroupUUID, deviceUUID:deviceUUID) else {
                XCTFail()
                return
            }
        }

        self.performServerTest(testAccount:testAccount) { expectation, testCreds in
            let headers = self.setupHeaders(testUser:testAccount, accessToken: testCreds.accessToken, deviceUUID:deviceUUID)
            
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
    
    @discardableResult
    func downloadTextFile(testAccount:TestAccount = .primaryOwningAccount, masterVersionExpectedWithDownload:Int, expectUpdatedMasterUpdate:Bool = false, appMetaData:AppMetaData? = nil, uploadFileVersion:FileVersionInt = 0, downloadFileVersion:FileVersionInt = 0, uploadFileRequest:UploadFileRequest? = nil, fileSize:Int64? = nil, expectedError: Bool = false) -> DownloadFileResponse? {
    
        let deviceUUID = Foundation.UUID().uuidString
        let masterVersion:Int64 = 0
        
        var actualUploadFileRequest:UploadFileRequest!
        var actualFileSize:Int64!
        
        let beforeUploadTime = Date()
        var afterUploadTime:Date!
        var fileUUID:String!
        var actualSharingGroupUUID: String!
        
        if uploadFileRequest == nil {
            guard let uploadResult = uploadTextFile(deviceUUID:deviceUUID, fileVersion:uploadFileVersion, masterVersion:masterVersion, cloudFolderName: ServerTestCase.cloudFolderName, appMetaData:appMetaData),
                let sharingGroupUUID = uploadResult.sharingGroupUUID else {
                XCTFail()
                return nil
            }
            
            actualSharingGroupUUID = sharingGroupUUID
            
            fileUUID = uploadResult.request.fileUUID
            actualUploadFileRequest = uploadResult.request
            actualFileSize = uploadResult.fileSize
            self.sendDoneUploads(expectedNumberOfUploads: 1, deviceUUID:deviceUUID, masterVersion: masterVersion, sharingGroupUUID: sharingGroupUUID)
            afterUploadTime = Date()
        }
        else {
            actualUploadFileRequest = uploadFileRequest
            actualFileSize = fileSize
            actualSharingGroupUUID = uploadFileRequest?.sharingGroupUUID
        }
        
        var result:DownloadFileResponse?
        
        self.performServerTest(testAccount:testAccount) { expectation, testCreds in
            let headers = self.setupHeaders(testUser:testAccount, accessToken: testCreds.accessToken, deviceUUID:deviceUUID)
            
            let downloadFileRequest = DownloadFileRequest(json: [
                DownloadFileRequest.fileUUIDKey: actualUploadFileRequest!.fileUUID,
                DownloadFileRequest.masterVersionKey : "\(masterVersionExpectedWithDownload)",
                DownloadFileRequest.fileVersionKey : downloadFileVersion,
                DownloadFileRequest.appMetaDataVersionKey: appMetaData?.version as Any,
                ServerEndpoint.sharingGroupUUIDKey: actualSharingGroupUUID
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
                    
                    if let dict = dict,
                        let downloadFileResponse = DownloadFileResponse(json: dict) {
                        result = downloadFileResponse
                        if expectUpdatedMasterUpdate {
                            XCTAssert(downloadFileResponse.masterVersionUpdate != nil)
                        }
                        else {
                            XCTAssert(downloadFileResponse.masterVersionUpdate == nil)
                            XCTAssert(downloadFileResponse.fileSizeBytes == actualFileSize, "downloadFileResponse.fileSizeBytes: \(String(describing: downloadFileResponse.fileSizeBytes)); actualFileSize: \(actualFileSize)")
                            XCTAssert(downloadFileResponse.appMetaData == appMetaData?.contents)
                            guard let type = downloadFileResponse.cloudStorageType,
                                let _ = CloudStorageType(rawValue: type) else {
                                XCTFail()
                                return
                            }
                            XCTAssert(downloadFileResponse.checkSum != nil)
                        }
                    }
                    else {
                        XCTFail()
                    }
                }
                
                expectation.fulfill()
            }
        }
        
        if let afterUploadTime = afterUploadTime, let fileUUID = fileUUID {
            checkThatDateFor(fileUUID: fileUUID, isBetween: beforeUploadTime, end: afterUploadTime, sharingGroupUUID: actualSharingGroupUUID)
        }
        
        return result
    }
    
    func checkThatDateFor(fileUUID: String, isBetween start: Date, end: Date, sharingGroupUUID:String) {
        guard let (files, _) = getIndex(sharingGroupUUID:sharingGroupUUID),
            let fileInfo = files else {
            XCTFail()
            return
        }

        let file = fileInfo.filter({$0.fileUUID == fileUUID})[0]
        // let comp1 = file.creationDate!.compare(start)
        
        // I've been having problems here comparing dates. It seems that this is akin to the problem of comparing real numbers, and the general rule that you shouldn't test real numbers for equality. To help in this, I'm going to just use the mm/dd/yy and hh:mm:ss components of the dates.
        func clean(_ date: Date) -> Date {
            let orig = Calendar.current.dateComponents(
                [.day, .month, .year, .hour, .minute, .second], from: date)

            var new = DateComponents()
            new.day = orig.day
            new.month = orig.month
            new.year = orig.year
            new.hour = orig.hour
            new.minute = orig.minute
            new.second = orig.second

            return Calendar.current.date(from: new)!
        }
        
        let cleanCreationDate = clean(file.creationDate!)
        let cleanStart = clean(start)
        let cleanEnd = clean(end)
        
        XCTAssert(cleanStart <= cleanCreationDate, "start: \(cleanStart); file.creationDate: \(cleanCreationDate)")
        XCTAssert(cleanCreationDate <= cleanEnd, "file.creationDate: \(cleanCreationDate); end: \(cleanEnd)")
    }
    
    @discardableResult
    func uploadFile(creds: CloudStorage, deviceUUID:String, fileContents: String, uploadRequest:UploadFileRequest, options:CloudStorageFileNameOptions? = nil, failureExpected: Bool = false, errorExpected: CloudStorageError? = nil) -> String {
        
        let fileContentsData = fileContents.data(using: .ascii)!
        let cloudFileName = uploadRequest.cloudFileName(deviceUUID:deviceUUID, mimeType: uploadRequest.mimeType)
        
        let exp = expectation(description: "\(#function)\(#line)")

        creds.uploadFile(cloudFileName: cloudFileName, data: fileContentsData, options: options) { result in
            switch result {
            case .success(let size):
                XCTAssert(size == fileContents.count)
                Log.debug("size: \(size)")
                if failureExpected {
                    XCTFail()
                }
            case .failure(let error):
                Log.debug("uploadFile: \(error)")
                if !failureExpected {
                    XCTFail()
                }
                
                if let errorExpected = errorExpected {
                    guard let error = error as? CloudStorageError else {
                        XCTFail()
                        exp.fulfill()
                        return
                    }
                    
                    XCTAssert(error == errorExpected)
                }
            }
            
            exp.fulfill()
        }
        
        waitForExpectations(timeout: 10, handler: nil)
        return cloudFileName
    }
    
    func addSharingGroup(sharingGroupUUID: String, sharingGroupName: String? = nil) -> Bool {
        let result = SharingGroupRepository(db).add(sharingGroupUUID: sharingGroupUUID, sharingGroupName: sharingGroupName)
        
        switch result {
        case .success:
            return true
        
        default:
            XCTFail()
        }
        
        return false
    }
}

extension ServerTestCase : ConstantsDelegate {
    // A hack to get access to Server.json during testing.
    public func configFilePath(forConstants:Constants) -> String {
        return "/tmp"
    }
}

