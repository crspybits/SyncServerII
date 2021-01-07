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
import ServerShared
import HeliumLogger
import Kitura
import ServerAccount

#if os(Linux)
    import Glibc
#else
    import Darwin.C
#endif

class ServerTestCase : XCTestCase {
    var db:Database!
    
    override func setUp() {
        super.setUp()
        Log.logger = HeliumLogger()
        HeliumLogger.use(.debug)
        
        // The same file is assumed to contain both the server configuration and test configuration keys.
#if os(Linux)
        try! Configuration.setup(configFileFullPath: "./ServerTests.json", testConfigFileFullPath: "./ServerTests.json")
#else
        // Assume that the configuration file(s) have been copied to /tmp before running the test.
        try! Configuration.setup(configFileFullPath: "/tmp/ServerTests.json", testConfigFileFullPath: "/tmp/ServerTests.json")
#endif

        Log.info("About to open...")
        self.db = Database()
        Log.info("Opened.")
        
        Database.remove(db: db)
        _ = Database.setup(db: db)
        
        TestAccount.registerHandlers()
        
        MockStorage.reset()
    }
    
    override func tearDown() {
        super.tearDown()
        
        Log.info("About to close...")
        // Otherwise we can have too many db connections open during testing.
        self.db.close()
        self.db = nil
        Log.info("Closed")
    }

    // When I added UploaderCommon I started getting complaints from the compiler. Oddly, the following fixes it.
#if os(Linux)
    func expectation(description: String) -> XCTestExpectation {
        super.expectation(description: description)
    }
    
    func waitForExpectations(timeout: TimeInterval, handler: XCWaitCompletionHandler?) {
        super.waitForExpectations(timeout: timeout, handler: handler)
    }
#else
    override func expectation(description: String) -> XCTestExpectation {
        super.expectation(description: description)
    }
    
    override func waitForExpectations(timeout: TimeInterval, handler: XCWaitCompletionHandler?) {
        super.waitForExpectations(timeout: timeout, handler: handler)
    }
#endif

    @discardableResult
    func checkOwingUserForSharingGroupUser(sharingGroupUUID: String, sharingUserId: UserId, sharingUser:TestAccount, owningUser: TestAccount) -> Bool {
        
        let sharingUserKey = SharingGroupUserRepository.LookupKey.primaryKeys(sharingGroupUUID: sharingGroupUUID, userId: sharingUserId)
        let sharingResult = SharingGroupUserRepository(db).lookup(key: sharingUserKey, modelInit: SharingGroupUser.init)
        var sharingGroupUser1: Server.SharingGroupUser!
        switch sharingResult {
        case .found(let model):
            sharingGroupUser1 = (model as! Server.SharingGroupUser)
        case .error, .noObjectFound:
            XCTFail()
            return false
        }
        
        guard let (_, sharingGroups) = getIndex(testAccount: sharingUser) else {
            XCTFail()
            return false
        }
        
        let filtered = sharingGroups.filter {$0.sharingGroupUUID == sharingGroupUUID}
        guard filtered.count == 1 else {
            XCTFail()
            return false
        }
        
        let sharingGroup = filtered[0]
        
        if sharingUser.scheme.userType == .owning {
            XCTAssert(sharingGroup.cloudStorageType == nil)
            XCTAssert(sharingGroupUser1.owningUserId == nil)
            return sharingGroupUser1.owningUserId == nil
        }
        
        guard let owningUserId = sharingGroupUser1.owningUserId else {
            XCTFail()
            return false
        }
        
        let owningUserKey = SharingGroupUserRepository.LookupKey.primaryKeys(sharingGroupUUID: sharingGroupUUID, userId: owningUserId)
        let owningResult = SharingGroupUserRepository(db).lookup(key: owningUserKey, modelInit: SharingGroupUser.init)
        var sharingGroupUser2: Server.SharingGroupUser!
        switch owningResult {
        case .found(let model):
            sharingGroupUser2 = (model as! Server.SharingGroupUser)
        case .error, .noObjectFound:
            XCTFail()
            return false
        }
        
        guard owningUser.scheme.userType == .owning,
            sharingGroupUser2.owningUserId == nil else {
            XCTFail()
            return false
        }
        
        let userKey = UserRepository.LookupKey.userId(owningUserId)
        let userResult = UserRepository(db).lookup(key: userKey, modelInit: User.init)
        
        var resultOwningUser: User!
        
        switch userResult {
        case .found(let model):
            guard let userObj = model as? User,
                userObj.accountType == owningUser.scheme.accountName else {
                XCTFail()
                return false
            }
            resultOwningUser = userObj

        case .error, .noObjectFound:
            XCTFail()
            return false
        }
        
        // Make sure that sharing groups returned from the server with the Index reflect, for sharing users, their "parent" owning user for the sharing group.
        guard let ownersCloudStorageType = sharingGroup.cloudStorageType else {
            XCTFail()
            return false
        }

        guard AccountScheme(.accountName(resultOwningUser.accountType))?.cloudStorageType == ownersCloudStorageType else {
            XCTFail()
            return false
        }
        
        return true
    }
    
    // The second sharing account joined is returned as the sharingGroupUUID
    @discardableResult
    func redeemWithAnExistingOtherSharingAccount() -> (TestAccount, sharingGroupUUID: String)? {
        var returnResult: (TestAccount, String)?
        
        let deviceUUID = Foundation.UUID().uuidString
        let sharingGroupUUID = Foundation.UUID().uuidString
        let owningUser:TestAccount = .primaryOwningAccount

        guard let _ = self.addNewUser(testAccount: owningUser, sharingGroupUUID: sharingGroupUUID, deviceUUID:deviceUUID) else {
            XCTFail()
            return nil
        }
        
        var sharingInvitationUUID:String! = createSharingInvitation(testAccount: owningUser, permission: .read, sharingGroupUUID:sharingGroupUUID)
        
        let sharingUser: TestAccount = .primarySharingAccount
        guard let _ = redeemSharingInvitation(sharingUser: sharingUser, sharingInvitationUUID: sharingInvitationUUID) else {
            XCTFail()
            return nil
        }
        
        // Primary sharing account user now exists.

        let sharingGroupUUID2 = Foundation.UUID().uuidString

        // Create a second sharing group and invite/redeem the primary sharing account user.
        guard createSharingGroup(testAccount: owningUser, sharingGroupUUID: sharingGroupUUID2, deviceUUID:deviceUUID) else {
            XCTFail()
            return nil
        }
        
        sharingInvitationUUID = createSharingInvitation(testAccount: owningUser, permission: .write, sharingGroupUUID:sharingGroupUUID2)
        
        guard let result = redeemSharingInvitation(sharingUser: sharingUser, sharingInvitationUUID: sharingInvitationUUID) else {
            XCTFail()
            return nil
        }

        if checkOwingUserForSharingGroupUser(sharingGroupUUID: sharingGroupUUID2, sharingUserId: result.userId, sharingUser: sharingUser, owningUser: owningUser) {
            returnResult = (sharingUser, sharingGroupUUID2)
        }
        
        return returnResult
    }
    
    @discardableResult
    func downloadAppMetaDataVersion(testAccount:TestAccount = .primaryOwningAccount, deviceUUID: String, fileUUID: String, sharingGroupUUID: String, expectedError: Bool = false) -> DownloadAppMetaDataResponse? {

        var result:DownloadAppMetaDataResponse?
        
        self.performServerTest(testAccount:testAccount) { [weak self] expectation, testCreds in
            guard let self = self else { return }
            let headers = self.setupHeaders(testUser:testAccount, accessToken: testCreds.accessToken, deviceUUID:deviceUUID)

            let downloadAppMetaDataRequest = DownloadAppMetaDataRequest()
            downloadAppMetaDataRequest.fileUUID = fileUUID
            downloadAppMetaDataRequest.sharingGroupUUID = sharingGroupUUID
            
            if !downloadAppMetaDataRequest.valid() {
                if !expectedError {
                    XCTFail()
                }
                expectation.fulfill()
                return
            }
            
            self.performRequest(route: ServerEndpoints.downloadAppMetaData, headers: headers, urlParameters: "?" + downloadAppMetaDataRequest.urlParameters()!, body:nil) { response, dict in
                Log.info("Status code: \(response!.statusCode)")
                
                if expectedError {
                    XCTAssert(response!.statusCode != .OK, "Did not work on failing downloadAppMetaDataRequest request")
                }
                else {
                    XCTAssert(response!.statusCode == .OK, "Did not work on downloadAppMetaDataRequest request")

                    if let dict = dict,
                        let downloadAppMetaDataResponse = try? DownloadAppMetaDataResponse.decode(dict) {
                        result = downloadAppMetaDataResponse
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
        
        performServerTest { [weak self] expectation in
            guard let self = self else { return }
            self.performRequest(route: ServerEndpoints.healthCheck) { response, dict in
                XCTAssert(response!.statusCode == .OK, "Failed on healthcheck request")

                guard let dict = dict, let healthCheckResponse = try? HealthCheckResponse.decode(dict) else {
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
    
    func deleteFile(testAccount: TestAccount, cloudFileName: String, options: CloudStorageFileNameOptions, fileNotFoundOK: Bool = false) {
        
        let expectation = self.expectation(description: "expectation")

        testAccount.scheme.deleteFile(testAccount: testAccount, cloudFileName: cloudFileName, options: options, fileNotFoundOK: fileNotFoundOK, expectation: expectation)
        
        waitForExpectations(timeout: 20.0, handler: nil)
    }
    
    @discardableResult
    func addNewUser(testAccount:TestAccount = .primaryOwningAccount, sharingGroupUUID: String, deviceUUID:String, cloudFolderName: String? = ServerTestCase.cloudFolderName, sharingGroupName:String? = nil) -> AddUserResponse? {
        var result:AddUserResponse?

        if let fileName = Configuration.server.owningUserAccountCreation.initialFileName {
            // Need to delete the initialization file in the test account, so that if we're creating the user test account for a 2nd, 3rd etc time, we don't fail.
            let options = CloudStorageFileNameOptions(cloudFolderName: cloudFolderName, mimeType: "text/plain")
            Log.debug("About to delete file.")
            deleteFile(testAccount: testAccount, cloudFileName: fileName, options: options, fileNotFoundOK: true)
            result = addNewUser2(testAccount:testAccount, sharingGroupUUID: sharingGroupUUID, deviceUUID:deviceUUID, cloudFolderName: cloudFolderName, sharingGroupName: sharingGroupName)
        }
        else {
            result = addNewUser2(testAccount:testAccount, sharingGroupUUID: sharingGroupUUID, deviceUUID:deviceUUID, cloudFolderName: cloudFolderName, sharingGroupName: sharingGroupName)
        }
        
        return result
    }
    
    private func addNewUser2(testAccount:TestAccount, sharingGroupUUID: String, deviceUUID:String, cloudFolderName: String?, sharingGroupName:String?) -> AddUserResponse? {
        var result:AddUserResponse?
        
        let addUserRequest = AddUserRequest()
        addUserRequest.cloudFolderName = cloudFolderName
        addUserRequest.sharingGroupName = sharingGroupName
        addUserRequest.sharingGroupUUID = sharingGroupUUID
        
        self.performServerTest(testAccount:testAccount) { [weak self] expectation, creds in
            guard let self = self else { return }
            
            guard let accessToken = creds.accessToken else {
                XCTFail()
                expectation.fulfill()
                return
            }
            
            let headers = self.setupHeaders(testUser: testAccount, accessToken: accessToken, deviceUUID:deviceUUID)
            
            var queryParams:String?
            if let params = addUserRequest.urlParameters() {
                queryParams = "?" + params
            }
            
            self.performRequest(route: ServerEndpoints.addUser, headers: headers, urlParameters: queryParams) { response, dict in
                Log.info("Status code: \(String(describing: response?.statusCode))")
                
                guard let response = response else {
                    XCTFail()
                    expectation.fulfill()
                    return
                }
                
                XCTAssert(response.statusCode == .OK, "Did not work on addUser request: \(response.statusCode)")
                
                if let dict = dict, let addUserResponse = try? AddUserResponse.decode(dict) {
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
    func createSharingGroup(testAccount:TestAccount = .primaryOwningAccount, sharingGroupUUID:String, deviceUUID:String, sharingGroup: ServerShared.SharingGroup? = nil, errorExpected: Bool = false) -> Bool {
        var result: Bool = false
        
        let createRequest = CreateSharingGroupRequest()
        createRequest.sharingGroupName = sharingGroup?.sharingGroupName
        createRequest.sharingGroupUUID = sharingGroupUUID
        
        self.performServerTest(testAccount:testAccount) { [weak self] expectation, creds in
            guard let self = self else { return }
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
                    if let dict = dict, let _ = try? CreateSharingGroupResponse.decode(dict) {
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
    func updateSharingGroup(testAccount:TestAccount = .primaryOwningAccount, deviceUUID:String, sharingGroup: ServerShared.SharingGroup, expectFailure: Bool = false) -> Bool {
        var result: Bool = false
        
        let updateRequest = UpdateSharingGroupRequest()
        updateRequest.sharingGroupUUID = sharingGroup.sharingGroupUUID
        updateRequest.sharingGroupName = sharingGroup.sharingGroupName
        
        self.performServerTest(testAccount:testAccount) { [weak self] expectation, creds in
            guard let self = self else { return }
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

                    if let dict = dict, let _ = try? UpdateSharingGroupResponse.decode(dict) {
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
    func removeSharingGroup(testAccount:TestAccount = .primaryOwningAccount, deviceUUID:String, sharingGroupUUID: String) -> Bool {
        var result: Bool = false
        
        let removeRequest = RemoveSharingGroupRequest()
        removeRequest.sharingGroupUUID = sharingGroupUUID
        
        self.performServerTest(testAccount:testAccount) { [weak self] expectation, creds in
            guard let self = self else { return }
            let headers = self.setupHeaders(testUser: testAccount, accessToken: creds.accessToken, deviceUUID:deviceUUID)
            
            var queryParams:String?
            if let params = removeRequest.urlParameters() {
                queryParams = "?" + params
            }
            
            self.performRequest(route: ServerEndpoints.removeSharingGroup, headers: headers, urlParameters: queryParams) { response, dict in
                Log.info("Status code: \(response!.statusCode)")
                XCTAssert(response!.statusCode == .OK, "Did not work on remove sharing group request: \(response!.statusCode)")

                if let dict = dict, let _ = try? RemoveSharingGroupResponse.decode(dict) {
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
    
    @discardableResult
    func removeUserFromSharingGroup(testAccount:TestAccount = .primaryOwningAccount, deviceUUID:String, sharingGroupUUID: String) -> Bool {
        var result: Bool = false
        
        let removeRequest = RemoveUserFromSharingGroupRequest()
        removeRequest.sharingGroupUUID = sharingGroupUUID
        
        self.performServerTest(testAccount:testAccount) { [weak self] expectation, creds in
            guard let self = self else { return }
            let headers = self.setupHeaders(testUser: testAccount, accessToken: creds.accessToken, deviceUUID:deviceUUID)
            
            var queryParams:String?
            if let params = removeRequest.urlParameters() {
                queryParams = "?" + params
            }
            
            self.performRequest(route: ServerEndpoints.removeUserFromSharingGroup, headers: headers, urlParameters: queryParams) { response, dict in
                Log.info("Status code: \(response!.statusCode)")
                XCTAssert(response!.statusCode == .OK, "Did not work on remove user from sharing group request: \(response!.statusCode)")
                
                if let dict = dict, let _ = try? RemoveUserFromSharingGroupResponse.decode(dict) {
                    Log.debug("RemoveUserFromSharingGroupResponse: Decoded sucessfully")
                    result = true
                }
                else {
                    Log.error("RemoveUserFromSharingGroupResponse: Decode failed.")
                    XCTFail()
                }

                expectation.fulfill()
            }
        }
        
        return result
    }
    
    static let cloudFolderName = "CloudFolder"
    
    func getUploadsResults(testAccount:TestAccount = .primaryOwningAccount, deviceUUID:String, deferredUploadId: Int64) -> DeferredUploadStatus? {
        let request = GetUploadsResultsRequest()
        request.deferredUploadId = deferredUploadId
        
        guard let getUploadsResult = getUploadsResults(request: request, testAccount: testAccount, deviceUUID: deviceUUID) else {
            return nil
        }
        
        return getUploadsResult.status
    }
    
    func getUploadsResults(request:GetUploadsResultsRequest, testAccount:TestAccount = .primaryOwningAccount, deviceUUID:String) -> GetUploadsResultsResponse? {
        
        var result: GetUploadsResultsResponse?
        
        self.performServerTest(testAccount:testAccount) { [weak self] expectation, testCreds in
            guard let self = self else { return }
            let headers = self.setupHeaders(testUser: testAccount, accessToken: testCreds.accessToken, deviceUUID:deviceUUID)
            
            guard let parameters = request.urlParameters() else {
                Log.error("Could not generate urlParameters")
                expectation.fulfill()
                return
            }
            
            Log.debug("urlParameters(): \(parameters)")
            
            self.performRequest(route: ServerEndpoints.getUploadsResults, headers: headers, urlParameters: "?" + parameters) { response, dict in
                
                Log.info("Status code: \(String(describing: response?.statusCode))")

                guard let response = response else {
                    Log.error("Did not work on getUploadsResults request: Could not get response")
                    expectation.fulfill()
                    return
                }
                
                guard let dict = dict else {
                    Log.error("Did not work on getUploadsResults request: No dict")
                    expectation.fulfill()
                    return
                }
                
                guard response.statusCode == .OK else {
                    Log.error("Did not work on getUploadsResults request: Bad status code")
                    expectation.fulfill()
                    return
                }

                if let getUploadsResponse = try? GetUploadsResultsResponse.decode(dict) {
                    result = getUploadsResponse
                }
                else {
                    Log.error("Could not decode GetUploadsResultsResponse")
                }

                expectation.fulfill()
            }
        }
        
        return result
    }
    
    struct UploadFileResult {
        let request: UploadFileRequest
        let sharingGroupUUID:String?
        let uploadingUserId: UserId?
        let data: Data
        
        // The checksum sent along with the upload.
        let checkSum: String?
        let response: UploadFileResponse?
    }
    
    enum AddUser {
        case no(sharingGroupUUID: String)
        case yes
    }
    
    // statusCodeExpected is only used if an error is expected.
    // owningAccountType will be the same type as testAccount when an owning user is uploading (you can pass nil here), and the type of the "parent" owner when a sharing user is uploading.
    // If dataToUpload is present, `file` is not used.
    // `vNUpload` signals whether or not to wait for Uploader run to complete.
    @discardableResult
    func uploadServerFile(uploadIndex: Int32, uploadCount: Int32, testAccount:TestAccount = .primaryOwningAccount, fileLabel: String?, mimeType: String? = nil, owningAccountType: AccountScheme.AccountName? = nil, deviceUUID:String = Foundation.UUID().uuidString, fileUUID:String? = nil, addUser:AddUser = .yes, cloudFolderName:String? = ServerTestCase.cloudFolderName, appMetaData:String? = nil, errorExpected:Bool = false, undelete: Int32 = 0, file: TestFile? = .test1, dataToUpload: Data? = nil, fileGroup:FileGroup? = nil, changeResolverName: String? = nil, vNUpload: Bool = false, statusCodeExpected: HTTPStatusCode? = nil) -> UploadFileResult? {
    
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
        
        var data:Data! = dataToUpload
        
        if data == nil {
            guard let file = file else {
                return nil
            }
            
            switch file.contents {
            case .string(let string):
                data = string.data(using: .utf8)!
            case .url(let url):
                data = try? Data(contentsOf: url)
            }
        }
        
        guard data != nil else {
            return nil
        }
        
        var checkSumType: AccountScheme.AccountName
        if let owningAccountType = owningAccountType {
            checkSumType = owningAccountType
        }
        else {
            checkSumType = testAccount.scheme.accountName
        }
        
        let requestCheckSum = file?.checkSum(type: checkSumType)
        Log.info("Starting runUploadTest: uploadTextFile: requestCheckSum: \(String(describing: requestCheckSum))")

        let uploadRequest = UploadFileRequest()
        uploadRequest.fileUUID = fileUUIDToSend
        uploadRequest.mimeType = mimeType
        uploadRequest.fileGroupUUID = fileGroup?.fileGroupUUID
        uploadRequest.sharingGroupUUID = sharingGroupUUID
        uploadRequest.checkSum = requestCheckSum
        uploadRequest.uploadIndex = uploadIndex
        uploadRequest.uploadCount = uploadCount
        uploadRequest.objectType = fileGroup?.objectType
        uploadRequest.fileLabel = fileLabel
        
        if let appMetaData = appMetaData {
            uploadRequest.appMetaData = AppMetaData(contents: appMetaData)
        }
        
        uploadRequest.changeResolverName = changeResolverName
        
        Log.info("Starting runUploadTest: uploadTextFile: uploadRequest: \(String(describing: uploadRequest.toDictionary))")
        
        guard uploadRequest.valid() else {
            XCTFail()
            Log.error("Invalid upload request!")
            return nil
        }
        
        guard let response = runUploadTest(testAccount:testAccount, data:data, uploadRequest:uploadRequest, deviceUUID:deviceUUID, vNUpload: vNUpload, errorExpected: errorExpected, statusCodeExpected: statusCodeExpected) else {
            if !errorExpected {
                XCTFail()
            }
            return nil
        }
        
        Log.info("Completed runUploadTest: uploadTextFile")
        
        let checkSum = file?.checkSum(type: checkSumType)
        
        return UploadFileResult(request: uploadRequest, sharingGroupUUID: sharingGroupUUID, uploadingUserId: uploadingUserId, data: data, checkSum: checkSum, response: response)
    }
    
    public struct FileGroup {
        let fileGroupUUID: String
        let objectType: String
        
        public init(fileGroupUUID: String, objectType: String) {
            self.fileGroupUUID = fileGroupUUID
            self.objectType = objectType
        }
    }
    
    @discardableResult
    func uploadTextFile(uploadIndex: Int32 = 1, uploadCount: Int32 = 1, testAccount:TestAccount = .primaryOwningAccount, mimeType: MimeType? = TestFile.test1.mimeType, owningAccountType: AccountScheme.AccountName? = nil, deviceUUID:String = Foundation.UUID().uuidString, fileUUID:String? = nil, addUser:AddUser = .yes, fileLabel: String?, cloudFolderName:String? = ServerTestCase.cloudFolderName, appMetaData:String? = nil, errorExpected:Bool = false, undelete: Int32 = 0, stringFile: TestFile? = .test1, dataToUpload: Data? = nil, fileGroup:FileGroup? = nil, changeResolverName: String? = nil, statusCodeExpected: HTTPStatusCode? = nil) -> UploadFileResult? {
    
        // This signals whether or not to wait for Uploader run to complete.
        let vNUpload = dataToUpload != nil && uploadIndex == uploadCount && !errorExpected
    
        return uploadServerFile(uploadIndex: uploadIndex, uploadCount: uploadCount, testAccount:testAccount, fileLabel: fileLabel, mimeType: mimeType?.rawValue, owningAccountType: owningAccountType, deviceUUID:deviceUUID, fileUUID:fileUUID, addUser:addUser, cloudFolderName:cloudFolderName, appMetaData:appMetaData, errorExpected:errorExpected, undelete: undelete, file: stringFile, dataToUpload: dataToUpload, fileGroup: fileGroup, changeResolverName: changeResolverName, vNUpload: vNUpload, statusCodeExpected: statusCodeExpected)
    }
    
    // Returns true iff the file could be uploaded.
    // `vNUpload` signals whether or not to wait for Uploader run to complete.
    @discardableResult
    func runUploadTest(testAccount:TestAccount = .primaryOwningAccount, data:Data, uploadRequest:UploadFileRequest, deviceUUID:String, vNUpload:Bool = false, errorExpected:Bool = false, statusCodeExpected: HTTPStatusCode? = nil) -> UploadFileResponse? {
        
        var result: UploadFileResponse?
        
        self.performServerTest(testAccount:testAccount, expectingUploaderToRun: vNUpload) { [weak self] expectation, testCreds in
            guard let self = self else { return }
            let headers = self.setupHeaders(testUser: testAccount, accessToken: testCreds.accessToken, deviceUUID:deviceUUID)
            
            // The method for ServerEndpoints.uploadFile really must be a POST to upload the file.
            XCTAssert(ServerEndpoints.uploadFile.method == .post)
            
            guard let parameters = uploadRequest.urlParameters() else {
                XCTFail()
                expectation.fulfill()
                return
            }
            
            Log.debug("uploadRequest.urlParameters(): \(parameters)")
            
            self.performRequest(route: ServerEndpoints.uploadFile, responseDictFrom: .header, headers: headers, urlParameters: "?" + parameters, body:data) { response, dict in
                
                Log.info("Status code: \(response!.statusCode)")

                if errorExpected {
                    if let statusCodeExpected = statusCodeExpected {
                        XCTAssert(response!.statusCode == statusCodeExpected)
                    }
                    else {
                        XCTAssert(response!.statusCode != .OK)
                    }
                }
                else {
                    guard response!.statusCode == .OK, dict != nil else {
                        XCTFail("Did not work on uploadFile request: \(response!.statusCode)")
                        expectation.fulfill()
                        return
                    }

                    if let uploadResponse = try? UploadFileResponse.decode(dict!) {
                        guard uploadResponse.updateDate != nil else {
                            XCTFail("A date was nil: uploadResponse.updateDate: \(String(describing: uploadResponse.updateDate))")
                            expectation.fulfill()
                            return
                        }
                        result = uploadResponse
                    }
                    else {
                        XCTFail("Could not decode UploadFileResponse")
                    }
                }

                expectation.fulfill()
            }
        }
        
        return result
    }
    
    func uploadFileUsingServer(testAccount:TestAccount = .primaryOwningAccount, uploadIndex:Int32 = 1, uploadCount:Int32 = 1, owningAccountType: AccountScheme.AccountName? = nil, deviceUUID:String = Foundation.UUID().uuidString, fileUUID:String = Foundation.UUID().uuidString, mimeType: MimeType = .jpeg, file: TestFile, fileLabel: String, addUser:AddUser = .yes, fileVersion:FileVersionInt = 0, appMetaData:String? = nil, fileGroup: FileGroup? = nil, changeResolverName: String? = nil, errorExpected:Bool = false) -> UploadFileResult? {
    
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
        
        guard case .url(let url) = file.contents,
            let data = try? Data(contentsOf: url) else {
            XCTFail()
            return nil
        }
        
        var checkSumType: AccountScheme.AccountName
        if let owningAccountType = owningAccountType {
            checkSumType = owningAccountType
        }
        else {
            checkSumType = testAccount.scheme.accountName
        }

        let uploadRequest = UploadFileRequest()
        uploadRequest.fileUUID = fileUUID
        uploadRequest.mimeType = mimeType.rawValue
        uploadRequest.sharingGroupUUID = sharingGroupUUID
        uploadRequest.checkSum = file.checkSum(type: checkSumType)
        uploadRequest.uploadCount = uploadCount
        uploadRequest.uploadIndex = uploadIndex
        uploadRequest.fileGroupUUID = fileGroup?.fileGroupUUID
        uploadRequest.changeResolverName = changeResolverName
        uploadRequest.objectType = fileGroup?.objectType
        uploadRequest.fileLabel = fileLabel
        
        guard uploadRequest.valid() else {
            XCTFail()
            return nil
        }
        
        if let appMetaData = appMetaData {
            uploadRequest.appMetaData = AppMetaData(contents: appMetaData)
        }
        
        Log.info("Starting runUploadTest: uploadJPEGFile")
        let uploadResponse = runUploadTest(testAccount: testAccount, data:data, uploadRequest:uploadRequest, deviceUUID:deviceUUID, errorExpected: errorExpected)
        Log.info("Completed runUploadTest: uploadJPEGFile")
        return UploadFileResult(request: uploadRequest, sharingGroupUUID: sharingGroupUUID, uploadingUserId:uploadingUserId, data: data, checkSum: file.checkSum(type: checkSumType), response: uploadResponse)
    }
    
    func uploadJPEGFile(testAccount:TestAccount = .primaryOwningAccount, uploadIndex:Int32 = 1, uploadCount:Int32 = 1, owningAccountType: AccountScheme.AccountName? = nil, deviceUUID:String = Foundation.UUID().uuidString, fileUUID:String = Foundation.UUID().uuidString, addUser:AddUser = .yes, fileVersion:FileVersionInt = 0, appMetaData:String? = nil, fileGroup: FileGroup? = nil, changeResolverName: String? = nil, errorExpected:Bool = false) -> UploadFileResult? {
        
        let jpegFile = TestFile.catJpg
        return uploadFileUsingServer(testAccount:testAccount, uploadIndex:uploadIndex, uploadCount:uploadCount, owningAccountType: owningAccountType, deviceUUID:deviceUUID, fileUUID:fileUUID, mimeType: .jpeg, file: jpegFile, fileLabel: UUID().uuidString, addUser:addUser, fileVersion:fileVersion, appMetaData:appMetaData, fileGroup: fileGroup, changeResolverName: changeResolverName, errorExpected:errorExpected)
    }
    
    func uploadMovFile(testAccount:TestAccount = .primaryOwningAccount, uploadIndex:Int32 = 1, uploadCount:Int32 = 1, owningAccountType: AccountScheme.AccountName? = nil, deviceUUID:String = Foundation.UUID().uuidString, fileUUID:String = Foundation.UUID().uuidString, addUser:AddUser = .yes, fileVersion:FileVersionInt = 0, appMetaData:String? = nil, fileGroup: FileGroup? = nil, changeResolverName: String? = nil, errorExpected:Bool = false) -> UploadFileResult? {
        
        let movFile = TestFile.catMov
        return uploadFileUsingServer(testAccount:testAccount, uploadIndex:uploadIndex, uploadCount:uploadCount, owningAccountType: owningAccountType, deviceUUID:deviceUUID, fileUUID:fileUUID, mimeType: .mov, file: movFile, fileLabel: UUID().uuidString, addUser:addUser, fileVersion:fileVersion, appMetaData:appMetaData, fileGroup: fileGroup, changeResolverName: changeResolverName, errorExpected:errorExpected)
    }
    
    func uploadPngFile(testAccount:TestAccount = .primaryOwningAccount, uploadIndex:Int32 = 1, uploadCount:Int32 = 1, owningAccountType: AccountScheme.AccountName? = nil, deviceUUID:String = Foundation.UUID().uuidString, fileUUID:String = Foundation.UUID().uuidString, addUser:AddUser = .yes, fileVersion:FileVersionInt = 0, appMetaData:String? = nil, fileGroup: FileGroup? = nil, changeResolverName: String? = nil, errorExpected:Bool = false) -> UploadFileResult? {
        
        let pngFile = TestFile.catPng
        return uploadFileUsingServer(testAccount:testAccount, uploadIndex:uploadIndex, uploadCount:uploadCount, owningAccountType: owningAccountType, deviceUUID:deviceUUID, fileUUID:fileUUID, mimeType: .png, file: pngFile, fileLabel: UUID().uuidString, addUser:addUser, fileVersion:fileVersion, appMetaData:appMetaData, fileGroup: fileGroup, changeResolverName: changeResolverName, errorExpected:errorExpected)
    }

    func getIndex(expectedFiles:[UploadFileRequest]? = nil, deviceUUID:String = Foundation.UUID().uuidString, sharingGroupUUID: String? = nil, expectedDeletionState:[String: Bool]? = nil, errorExpected: Bool = false) {
        
        let request = IndexRequest()
        request.sharingGroupUUID = sharingGroupUUID
    
        guard request.valid(),
            let parameters = request.urlParameters() else {
            XCTFail()
            return
        }
        
        self.performServerTest { [weak self] expectation, creds in
            guard let self = self else { return }
            let headers = self.setupHeaders(testUser: .primaryOwningAccount, accessToken: creds.accessToken, deviceUUID:deviceUUID)
            
            self.performRequest(route: ServerEndpoints.index, headers: headers, urlParameters: "?" + parameters, body:nil) { response, dict in
                Log.info("Status code: \(response!.statusCode)")

                if errorExpected {
                    XCTAssert(response!.statusCode != .OK)
                }
                else {
                    XCTAssert(response!.statusCode == .OK, "Did not work on IndexRequest request")
                    XCTAssert(dict != nil)

                    if let indexResponse = try? IndexResponse.decode(dict!) {
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
                                XCTAssert(expectedFile.mimeType == fileInfo.mimeType)
                                
                                if expectedDeletionState == nil {
                                    XCTAssert(fileInfo.deleted == false)
                                }
                                else {
                                    XCTAssert(fileInfo.deleted == expectedDeletionState![fileInfo.fileUUID])
                                }
                                
                                XCTAssert(fileInfo.cloudStorageType != nil)
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
    
    func getIndex(testAccount: TestAccount = .primaryOwningAccount, deviceUUID:String = Foundation.UUID().uuidString, sharingGroupUUID: String? = nil) -> ([FileInfo]?, [ServerShared.SharingGroup])? {
        var result:([FileInfo]?, [ServerShared.SharingGroup])?
        
        self.performServerTest(testAccount: testAccount) { [weak self] expectation, creds in
            guard let self = self else { return }
            let headers = self.setupHeaders(testUser: testAccount, accessToken: creds.accessToken, deviceUUID:deviceUUID)
            
            let request = IndexRequest()
            request.sharingGroupUUID = sharingGroupUUID
            
            guard request.valid() else {
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

                guard let indexResponse = try? IndexResponse.decode(dict!),
                    let groups = indexResponse.sharingGroups else {
                    expectation.fulfill()
                    XCTFail()
                    return
                }
                
                if sharingGroupUUID == nil {
                    XCTAssert(indexResponse.fileIndex == nil)
                }
                else {
                    XCTAssert(indexResponse.fileIndex != nil)
                }
                
                result = (indexResponse.fileIndex, groups)
                expectation.fulfill()
            }
        }
        
        return result
    }

    // If successful, returns the sharingInvitationUUID
    func createSharingInvitation(testAccount: TestAccount = .primaryOwningAccount, permission: Permission? = nil, numberAcceptors: UInt = 1, allowSharingAcceptance: Bool = true, deviceUUID:String = Foundation.UUID().uuidString, sharingGroupUUID: String, errorExpected: Bool = false) -> String? {
        
        var result: String?
        
        self.performServerTest(testAccount: testAccount) { [weak self] expectation, testCreds in
            guard let self = self else { return }
            let headers = self.setupHeaders(testUser:testAccount, accessToken: testCreds.accessToken, deviceUUID:deviceUUID)
            
            let request = CreateSharingInvitationRequest()
            request.sharingGroupUUID = sharingGroupUUID
            request.numberOfAcceptors = numberAcceptors
            request.allowSocialAcceptance = allowSharingAcceptance
            
            if permission != nil {
                request.permission = permission!
            }
            
            self.performRequest(route: ServerEndpoints.createSharingInvitation, headers: headers, urlParameters: "?" + request.urlParameters()!, body:nil) { response, dict in
                Log.info("Status code: \(response!.statusCode)")
                if errorExpected {
                    XCTAssert(response!.statusCode != .OK)
                }
                else {
                    XCTAssert(response!.statusCode == .OK, "Did not work on request: \(response!.statusCode)")
                    XCTAssert(dict != nil)
                    let response = try? CreateSharingInvitationResponse.decode(dict!)
                    result = response?.sharingInvitationUUID
                }
                
                expectation.fulfill()
            }
        }
        
        return result
    }
    
    // This also creates the owning user-- using .primaryOwningAccount
    func createSharingUser(withSharingPermission permission:Permission = .read, sharingUser:TestAccount = .dropbox1, addUser:AddUser = .yes, owningUserWhenCreating:TestAccount = .primaryOwningAccount, numberAcceptors: UInt = 1, allowSharingAcceptance: Bool = true, failureExpected: Bool = false, completion:((_ newSharingUserId:UserId?, _ sharingGroupUUID: String?, _ sharingInvitationUUID:String?)->())? = nil) {
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
                completion?(nil, nil, nil)
                return
            }
        }
        
        let sharingInvitationUUID: String! = createSharingInvitation(testAccount: owningUserWhenCreating, permission: permission, numberAcceptors: numberAcceptors, allowSharingAcceptance: allowSharingAcceptance, sharingGroupUUID:actualSharingGroupUUID)
        
        guard sharingInvitationUUID != nil else {
            XCTFail()
            return
        }
        
        let result = redeemSharingInvitation(sharingUser:sharingUser, sharingInvitationUUID: sharingInvitationUUID, errorExpected: failureExpected)
        if !failureExpected {
            XCTAssert(result?.userId != nil && result?.sharingGroupUUID != nil)
        }

        if failureExpected {
            completion?(nil, nil, nil)
        }
        else {
            // Check to make sure we have a new user:
            let userKey = UserRepository.LookupKey.accountTypeInfo(accountType: sharingUser.scheme.accountName, credsId: sharingUser.id())
            let userResults = UserRepository(self.db).lookup(key: userKey, modelInit: User.init)
            guard case .found(let model) = userResults else {
                Log.debug("sharingUser.type: \(sharingUser.scheme.accountName); sharingUser.id(): \(sharingUser.id())")
                XCTFail()
                completion?(nil, nil, nil)
                return
            }
            
            let key = SharingInvitationRepository.LookupKey.sharingInvitationUUID(uuid: sharingInvitationUUID)
            let results = SharingInvitationRepository(self.db).lookup(key: key, modelInit: SharingInvitation.init)
            
            if numberAcceptors <= 1 {
                guard case .noObjectFound = results else {
                    XCTFail()
                    completion?(nil, nil, nil)
                    return
                }
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
            
            completion?((model as! User).userId, actualSharingGroupUUID, sharingInvitationUUID)
        }
    }
    
    func redeemSharingInvitation(sharingUser:TestAccount, deviceUUID:String = Foundation.UUID().uuidString, canGiveCloudFolderName: Bool = true, sharingInvitationUUID:String? = nil, errorExpected:Bool=false) -> RedeemSharingInvitationResponse? {
    
        var result:RedeemSharingInvitationResponse?
        
        var actualCloudFolderName: String?
        if sharingUser.scheme.accountName == AccountScheme.google.accountName && canGiveCloudFolderName {
            actualCloudFolderName = ServerTestCase.cloudFolderName
        }
        
        self.performServerTest(testAccount:sharingUser) { [weak self] expectation, accountCreds in
            guard let self = self else { return }
            guard let accessToken = accountCreds.accessToken else {
                XCTFail()
                expectation.fulfill()
                return
            }
            
            let headers = self.setupHeaders(testUser: sharingUser, accessToken: accessToken, deviceUUID:deviceUUID)
            
            var urlParameters:String?
            
            if sharingInvitationUUID != nil {
                let request = RedeemSharingInvitationRequest()
                request.sharingInvitationUUID = sharingInvitationUUID!
                request.cloudFolderName = actualCloudFolderName
                urlParameters = "?" + request.urlParameters()!
            }
            
            self.performRequest(route: ServerEndpoints.redeemSharingInvitation, headers: headers, urlParameters: urlParameters, body:nil) { response, dict in
                Log.info("Status code: \(response!.statusCode)")
                
                if errorExpected {
                    XCTAssert(response!.statusCode != .OK, "Worked on request!")
                }
                else {
                    XCTAssert(response!.statusCode == .OK, "Did not work on request")
                    
                    if let dict = dict,
                        let redeemSharingInvitationResponse = try? RedeemSharingInvitationResponse.decode(dict) {
                        result = redeemSharingInvitationResponse
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
    
    func getSharingInvitationInfo(sharingInvitationUUID:String? = nil, errorExpected:Bool=false, httpStatusCodeExpected: HTTPStatusCode = .OK, completion:@escaping (_ result: GetSharingInvitationInfoResponse?, _ expectation: XCTestExpectation)->()) {

        self.performServerTest() { [weak self] expectation in
            guard let self = self else { return }
            var urlParameters:String?
            
            if sharingInvitationUUID != nil {
                let request = GetSharingInvitationInfoRequest()
                request.sharingInvitationUUID = sharingInvitationUUID!
                urlParameters = "?" + request.urlParameters()!
            }
            
            self.performRequest(route: ServerEndpoints.getSharingInvitationInfo, urlParameters: urlParameters) { response, dict in
                Log.info("Status code: \(response!.statusCode)")

                var result: GetSharingInvitationInfoResponse?
                
                if errorExpected {
                    XCTAssert(response!.statusCode == httpStatusCodeExpected, "ERROR: Worked on request!")
                }
                else {
                    XCTAssert(response!.statusCode == .OK, "Did not work on request")
                    
                    if let dict = dict,
                        let getSharingInvitationInfoResponse = try? GetSharingInvitationInfoResponse.decode(dict) {
                        result = getSharingInvitationInfoResponse
                    }
                    else {
                        XCTFail()
                    }
                }
                
                completion(result, expectation)
            }
        }
    }
    
    func getSharingInvitationInfo(sharingInvitationUUID:String? = nil, errorExpected:Bool=false, httpStatusCodeExpected: HTTPStatusCode = .OK) -> GetSharingInvitationInfoResponse? {
        var result:GetSharingInvitationInfoResponse?
        
        getSharingInvitationInfo(sharingInvitationUUID: sharingInvitationUUID, errorExpected: errorExpected, httpStatusCodeExpected: httpStatusCodeExpected) { response, exp in
            result = response
            exp.fulfill()
        }
        
        return result
    }
    
    func getSharingInvitationInfoWithSecondaryAuth(testAccount: TestAccount, sharingInvitationUUID:String? = nil, errorExpected:Bool=false, httpStatusCodeExpected: HTTPStatusCode = .OK, completion:@escaping (_ result: GetSharingInvitationInfoResponse?, _ expectation: XCTestExpectation)->()) {

        let deviceUUID = Foundation.UUID().uuidString
        
        self.performServerTest(testAccount: testAccount) { [weak self] expectation, account in
            guard let self = self else { return }
            var urlParameters:String?

            let headers = self.setupHeaders(testUser:testAccount, accessToken: account.accessToken, deviceUUID:deviceUUID)

            if sharingInvitationUUID != nil {
                let request = GetSharingInvitationInfoRequest()
                request.sharingInvitationUUID = sharingInvitationUUID!
                urlParameters = "?" + request.urlParameters()!
            }
            
            self.performRequest(route: ServerEndpoints.getSharingInvitationInfo, headers: headers, urlParameters: urlParameters) { response, dict in
                Log.info("Status code: \(response!.statusCode)")

                var result: GetSharingInvitationInfoResponse?
                
                if errorExpected {
                    XCTAssert(response!.statusCode == httpStatusCodeExpected, "ERROR: Worked on request!")
                }
                else {
                    XCTAssert(response!.statusCode == .OK, "Did not work on request")
                    
                    if let dict = dict,
                        let getSharingInvitationInfoResponse = try? GetSharingInvitationInfoResponse.decode(dict) {
                        result = getSharingInvitationInfoResponse
                    }
                    else {
                        XCTFail()
                    }
                }
                
                completion(result, expectation)
            }
        }
    }
    
    struct UploadDeletionResult {
        let sharingGroupUUID: String?
        let deferredUploadId: Int64?
    }
    
    func uploadDeletion(testAccount:TestAccount = .primaryOwningAccount, uploadDeletionRequest:UploadDeletionRequest, deviceUUID:String, addUser:Bool, expectError:Bool = false, expectingUploaderToRun: Bool = true) -> UploadDeletionResult? {
        
        var result: UploadDeletionResult?
        var sharingGroupUUID:String!

        if addUser {
            sharingGroupUUID = UUID().uuidString
            guard let _ = self.addNewUser(sharingGroupUUID: sharingGroupUUID, deviceUUID:deviceUUID) else {
                XCTFail()
                return nil
            }
        }

        self.performServerTest(testAccount:testAccount, expectingUploaderToRun: expectingUploaderToRun) { [weak self] expectation, testCreds in
            guard let self = self else { return }
            let headers = self.setupHeaders(testUser:testAccount, accessToken: testCreds.accessToken, deviceUUID:deviceUUID)
            
            self.performRequest(route: ServerEndpoints.uploadDeletion, headers: headers, urlParameters: "?" + uploadDeletionRequest.urlParameters()!) { response, dict in
                Log.info("Status code: \(response!.statusCode)")
                if expectError {
                    XCTAssert(response!.statusCode != .OK, "Did not fail on upload deletion request")
                }
                else {
                    if response!.statusCode == .OK {
                        if let dict = dict {
                            if let response = try? UploadDeletionResponse.decode(dict) {
                                result = UploadDeletionResult(sharingGroupUUID: sharingGroupUUID, deferredUploadId: response.deferredUploadId)
                            }
                            else {
                                XCTFail()
                            }
                        }
                        else {
                            XCTFail()
                        }
                    }
                    else {
                        XCTFail("Did not work on upload deletion request")
                    }
                }
                
                expectation.fulfill()
            }
        }
        
        return result
    }
    
    struct DownloadResult {
        let response: DownloadFileResponse?
        let data: Data?
    }
    
    func downloadFile(testAccount: TestAccount, fileUUID: String?, fileVersion: FileVersionInt, sharingGroupUUID: String, deviceUUID: String, expectedCheckSum: String? = nil, expectedError: Bool = false, contentsChangedExpected: Bool = false) -> DownloadResult? {
        var fileResponse:DownloadFileResponse?
        var dataResponse:Data?
        
        self.performServerTest(testAccount:testAccount) { [weak self] expectation, testCreds in
            guard let self = self else { return }
            let headers = self.setupHeaders(testUser:testAccount, accessToken: testCreds.accessToken, deviceUUID:deviceUUID)
            
            let downloadFileRequest = DownloadFileRequest()
            downloadFileRequest.fileUUID = fileUUID
            downloadFileRequest.fileVersion = fileVersion
            downloadFileRequest.sharingGroupUUID = sharingGroupUUID
            
            self.performRequest(route: ServerEndpoints.downloadFile, responseDictFrom:.header, headers: headers, urlParameters: "?" + downloadFileRequest.urlParameters()!, body:nil) { response, dict in
                Log.info("Status code: \(String(describing: response?.statusCode))")
                
                if expectedError {
                    XCTAssert(response?.statusCode != .OK, "Did not work on failing downloadFileRequest request")
                    XCTAssert(dict == nil)
                }
                else {
                    guard response?.statusCode == .OK else {
                        return
                    }
                    
                    guard dict != nil else {
                        return
                    }
                    
                    if let dict = dict,
                        let downloadFileResponse = try? DownloadFileResponse.decode(dict) {
                        fileResponse = downloadFileResponse
                        
                        var data = Data()
                        if let size = try? response?.readAllData(into: &data) {
                            Log.debug("data: \(data); data.count: \(data.count); size= \(String(describing: size))")
                            dataResponse = data
                        }
                        
                        XCTAssert(downloadFileResponse.contentsChanged == contentsChangedExpected)

                        var loadTesting = false
                        if let loadTestingCloudStorage = Configuration.server.loadTestingCloudStorage, loadTestingCloudStorage {
                            loadTesting = true
                        }
    
                        if let expectedCheckSum = expectedCheckSum, !loadTesting {
                            XCTAssert(downloadFileResponse.checkSum == expectedCheckSum, "downloadFileResponse.checkSum: \(String(describing: downloadFileResponse.checkSum)); actualCheckSum: \(String(describing: expectedCheckSum))")
                        }
                        
                        guard let _ = downloadFileResponse.cloudStorageType else {
                            XCTFail()
                            return
                        }
                        XCTAssert(downloadFileResponse.checkSum != nil)
                    }
                }
                
                expectation.fulfill()
            }
        }
        
        if fileResponse == nil && dataResponse == nil {
            return nil
        }
        else {
            return DownloadResult(response: fileResponse, data: dataResponse)
        }
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
            // 6/12/19; Due to Swift 5.0.1 issue; See https://stackoverflow.com/questions/56555005/swift-5-ubuntu-16-04-crash-with-datecomponents
            // not using Calendar.current
            let calendar = Calendar(identifier: .gregorian)

            let orig = calendar.dateComponents(
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
    func uploadFile(accountType: AccountScheme.AccountName, creds: CloudStorage, deviceUUID:String, testFile: TestFile, uploadRequest:UploadFileRequest, fileVersion: FileVersionInt, options:CloudStorageFileNameOptions? = nil, nonStandardFileName: String? = nil, failureExpected: Bool = false, errorExpected: CloudStorageError? = nil, expectAccessTokenRevokedOrExpired: Bool = false) -> String? {
    
        var fileContentsData: Data!
        
        switch testFile.contents {
        case .string(let fileContents):
            fileContentsData = fileContents.data(using: .ascii)!
        case .url(let url):
            fileContentsData = try? Data(contentsOf: url)
        }
        
        guard fileContentsData != nil else {
            XCTFail()
            return nil
        }
        
        var cloudFileName:String!
        if let nonStandardFileName = nonStandardFileName {
            cloudFileName = nonStandardFileName
        }
        else {
            guard let mimeType = uploadRequest.mimeType else {
                XCTFail()
                return nil
            }
            
            cloudFileName = Filename.inCloud(deviceUUID: deviceUUID, fileUUID: uploadRequest.fileUUID, mimeType: mimeType, fileVersion: fileVersion)
        }
        
        let exp = expectation(description: "\(#function)\(#line)")

        creds.uploadFile(cloudFileName: cloudFileName, data: fileContentsData, options: options) { result in
            switch result {
            case .success(let checkSum):
                XCTAssert(testFile.checkSum(type: accountType) == checkSum)
                Log.debug("checkSum: \(checkSum)")
                if failureExpected {
                    XCTFail()
                }
            case .failure(let error):
                if expectAccessTokenRevokedOrExpired {
                    XCTFail()
                }
                
                cloudFileName = nil
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
            case .accessTokenRevokedOrExpired:
                if !expectAccessTokenRevokedOrExpired {
                    XCTFail()
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
    
    func doAddFileIndex(userId:UserId = 1, sharingGroupUUID:String, createSharingGroup: Bool, changeResolverName: String? = nil) -> FileIndex? {

        if createSharingGroup {
            guard case .success = SharingGroupRepository(db).add(sharingGroupUUID: sharingGroupUUID) else {
                XCTFail()
                return nil
            }
            
            guard case .success = SharingGroupUserRepository(db).add(sharingGroupUUID: sharingGroupUUID, userId: userId, permission: .write, owningUserId: nil) else {
                XCTFail()
                return nil
            }
        }
        
        let fileIndex = FileIndex()
        fileIndex.lastUploadedCheckSum = "abcde"
        fileIndex.deleted = false
        fileIndex.fileUUID = Foundation.UUID().uuidString
        fileIndex.deviceUUID = Foundation.UUID().uuidString
        fileIndex.fileGroupUUID = Foundation.UUID().uuidString
        fileIndex.objectType = "MyObjectType"
        fileIndex.fileVersion = 1
        fileIndex.mimeType = "text/plain"
        fileIndex.userId = userId
        fileIndex.appMetaData = "{ \"foo\": \"bar\" }"
        fileIndex.creationDate = Date()
        fileIndex.updateDate = Date()
        fileIndex.sharingGroupUUID = sharingGroupUUID
        fileIndex.changeResolverName = changeResolverName
        fileIndex.fileLabel = "file1"
        
        let result1 = FileIndexRepository(db).add(fileIndex: fileIndex)
        guard case .success(let uploadId) = result1 else {
            XCTFail()
            return nil
        }

        fileIndex.fileIndexId = uploadId
        
        return fileIndex
    }
    
    func registerPushNotificationToken(request:RegisterPushNotificationTokenRequest, testAccount:TestAccount = .primaryOwningAccount, deviceUUID:String) -> RegisterPushNotificationTokenResponse? {
        
        var result: RegisterPushNotificationTokenResponse?
        
        self.performServerTest(testAccount:testAccount) { [weak self] expectation, testCreds in
            guard let self = self else { return }
            let headers = self.setupHeaders(testUser: testAccount, accessToken: testCreds.accessToken, deviceUUID:deviceUUID)
            
            guard let parameters = request.urlParameters() else {
                Log.error("Could not generate urlParameters")
                expectation.fulfill()
                return
            }
            
            Log.debug("urlParameters(): \(parameters)")
            
            self.performRequest(route: ServerEndpoints.registerPushNotificationToken, headers: headers, urlParameters: "?" + parameters) { response, dict in
                
                Log.info("Status code: \(String(describing: response?.statusCode))")

                guard let response = response else {
                    Log.error("Did not work on registerPushNotificationToken request: Could not get response")
                    expectation.fulfill()
                    return
                }
                
                guard let dict = dict else {
                    Log.error("Did not work on registerPushNotificationToken request: No dict")
                    expectation.fulfill()
                    return
                }
                
                guard response.statusCode == .OK else {
                    Log.error("Did not work on registerPushNotificationToken request: Bad status code")
                    expectation.fulfill()
                    return
                }

                if let registerResponse = try? RegisterPushNotificationTokenResponse.decode(dict) {
                    result = registerResponse
                }
                else {
                    Log.error("Could not decode registerPushNotificationToken")
                }

                expectation.fulfill()
            }
        }
        
        return result
    }
    
    func sendPushNotification(request:SendPushNotificationsRequest, testAccount:TestAccount = .primaryOwningAccount, deviceUUID:String) -> SendPushNotificationsResponse? {
        
        var result: SendPushNotificationsResponse?
        
        self.performServerTest(testAccount:testAccount) { [weak self] expectation, testCreds in
            guard let self = self else { return }
            let headers = self.setupHeaders(testUser: testAccount, accessToken: testCreds.accessToken, deviceUUID:deviceUUID)
            
            guard let parameters = request.urlParameters() else {
                Log.error("Could not generate urlParameters")
                expectation.fulfill()
                return
            }
            
            Log.debug("urlParameters(): \(parameters)")
            
            self.performRequest(route: ServerEndpoints.sendPushNotifications, headers: headers, urlParameters: "?" + parameters) { response, dict in
                
                Log.info("Status code: \(String(describing: response?.statusCode))")

                guard let response = response else {
                    Log.error("Did not work on sendPushNotification request: Could not get response")
                    expectation.fulfill()
                    return
                }
                
                guard let dict = dict else {
                    Log.error("Did not work on sendPushNotification request: No dict")
                    expectation.fulfill()
                    return
                }
                
                guard response.statusCode == .OK else {
                    Log.error("Did not work on sendPushNotification request: Bad status code")
                    expectation.fulfill()
                    return
                }

                if let sendResponse = try? SendPushNotificationsResponse.decode(dict) {
                    result = sendResponse
                }
                else {
                    Log.error("Could not decode sendPushNotification")
                }

                expectation.fulfill()
            }
        }
        
        return result
    }
}

