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
        
        Log.info("About to close...")
        // Otherwise we can have too many db connections open during testing.
        self.db.close()
        Log.info("Closed")
    }
    
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
        
        if sharingUser.type.userType == .owning {
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
        
        guard owningUser.type.userType == .owning,
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
                userObj.accountType == owningUser.type else {
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
        
        guard resultOwningUser.accountType.cloudStorageType?.rawValue == ownersCloudStorageType else {
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
        
        var sharingInvitationUUID:String!
        
        createSharingInvitation(testAccount: owningUser, permission: .read, sharingGroupUUID:sharingGroupUUID) { expectation, invitationUUID in
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
        guard createSharingGroup(testAccount: owningUser, sharingGroupUUID: sharingGroupUUID2, deviceUUID:deviceUUID) else {
            XCTFail()
            return nil
        }
        
        createSharingInvitation(testAccount: owningUser, permission: .write, sharingGroupUUID:sharingGroupUUID2) { expectation, invitationUUID in
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

        if checkOwingUserForSharingGroupUser(sharingGroupUUID: sharingGroupUUID2, sharingUserId: result.userId, sharingUser: sharingUser, owningUser: owningUser) {
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
                        let uploadAppMetaDataResponse = try? UploadAppMetaDataResponse.decode(dict) {
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

            let downloadAppMetaDataRequest = DownloadAppMetaDataRequest()
            downloadAppMetaDataRequest.fileUUID = fileUUID
            downloadAppMetaDataRequest.masterVersion = masterVersionExpectedWithDownload
            downloadAppMetaDataRequest.appMetaDataVersion = appMetaDataVersion
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
    
    func deleteFile(testAccount: TestAccount, cloudFileName: String, options: CloudStorageFileNameOptions) {
        
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
                
                creds.deleteFile(cloudFileName:cloudFileName, options:options) { result in
                    switch result {
                    case .success:
                        break
                    case .accessTokenRevokedOrExpired:
                        XCTFail()
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
            creds.deleteFile(cloudFileName:cloudFileName, options:options) { result in
                switch result {
                case .success:
                    break
                case .accessTokenRevokedOrExpired:
                    XCTFail()
                case .failure:
                    XCTFail()
                }

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
                    case .failure, .accessTokenRevokedOrExpired:
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
                case .failure, .accessTokenRevokedOrExpired:
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
        
        let addUserRequest = AddUserRequest()
        addUserRequest.cloudFolderName = cloudFolderName
        addUserRequest.sharingGroupName = sharingGroupName
        addUserRequest.sharingGroupUUID = sharingGroupUUID
        
        self.performServerTest(testAccount:testAccount) { expectation, creds in
            let headers = self.setupHeaders(testUser: testAccount, accessToken: creds.accessToken, deviceUUID:deviceUUID)
            
            var queryParams:String?
            if let params = addUserRequest.urlParameters() {
                queryParams = "?" + params
            }
            
            self.performRequest(route: ServerEndpoints.addUser, headers: headers, urlParameters: queryParams) { response, dict in
                Log.info("Status code: \(response!.statusCode)")
                XCTAssert(response!.statusCode == .OK, "Did not work on addUser request: \(response!.statusCode)")
                
                
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
    func createSharingGroup(testAccount:TestAccount = .primaryOwningAccount, sharingGroupUUID:String, deviceUUID:String, sharingGroup: SyncServerShared.SharingGroup? = nil, errorExpected: Bool = false) -> Bool {
        var result: Bool = false
        
        let createRequest = CreateSharingGroupRequest()
        createRequest.sharingGroupName = sharingGroup?.sharingGroupName
        createRequest.sharingGroupUUID = sharingGroupUUID
        
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
    func updateSharingGroup(testAccount:TestAccount = .primaryOwningAccount, deviceUUID:String, sharingGroup: SyncServerShared.SharingGroup, masterVersion: MasterVersionInt, expectMasterVersionUpdate: Bool = false, expectFailure: Bool = false) -> Bool {
        var result: Bool = false
        
        let updateRequest = UpdateSharingGroupRequest()
        updateRequest.sharingGroupUUID = sharingGroup.sharingGroupUUID
        updateRequest.sharingGroupName = sharingGroup.sharingGroupName
        updateRequest.masterVersion = masterVersion
        
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

                    if let dict = dict, let response = try? UpdateSharingGroupResponse.decode(dict) {
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
        
        let removeRequest = RemoveSharingGroupRequest()
        removeRequest.sharingGroupUUID = sharingGroupUUID
        removeRequest.masterVersion = masterVersion
        
        self.performServerTest(testAccount:testAccount) { expectation, creds in
            let headers = self.setupHeaders(testUser: testAccount, accessToken: creds.accessToken, deviceUUID:deviceUUID)
            
            var queryParams:String?
            if let params = removeRequest.urlParameters() {
                queryParams = "?" + params
            }
            
            self.performRequest(route: ServerEndpoints.removeSharingGroup, headers: headers, urlParameters: queryParams) { response, dict in
                Log.info("Status code: \(response!.statusCode)")
                XCTAssert(response!.statusCode == .OK, "Did not work on remove sharing group request: \(response!.statusCode)")

                if let dict = dict, let response = try? RemoveSharingGroupResponse.decode(dict) {
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
        
        let removeRequest = RemoveUserFromSharingGroupRequest()
        removeRequest.sharingGroupUUID = sharingGroupUUID
        removeRequest.masterVersion = masterVersion
        
        self.performServerTest(testAccount:testAccount) { expectation, creds in
            let headers = self.setupHeaders(testUser: testAccount, accessToken: creds.accessToken, deviceUUID:deviceUUID)
            
            var queryParams:String?
            if let params = removeRequest.urlParameters() {
                queryParams = "?" + params
            }
            
            self.performRequest(route: ServerEndpoints.removeUserFromSharingGroup, headers: headers, urlParameters: queryParams) { response, dict in
                Log.info("Status code: \(response!.statusCode)")
                XCTAssert(response!.statusCode == .OK, "Did not work on remove user from sharing group request: \(response!.statusCode)")
                
                if let dict = dict, let response = try? RemoveUserFromSharingGroupResponse.decode(dict) {
                    Log.debug("RemoveUserFromSharingGroupResponse: Decoded sucessfully")
                    if let _ = response.masterVersionUpdate {
                        XCTAssert(expectMasterVersionUpdate)
                    }
                    else {
                        XCTAssert(!expectMasterVersionUpdate)
                    }
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
    
    struct UploadFileResult {
        let request: UploadFileRequest
        let sharingGroupUUID:String?
        let uploadingUserId: UserId?
        let data: Data
        
        // The checksum sent along with the upload.
        let checkSum: String
    }
    
    enum AddUser {
        case no(sharingGroupUUID: String)
        case yes
    }
    
    // statusCodeExpected is only used if an error is expected.
    // owningAccountType will be the same type as testAccount when an owning user is uploading (you can pass nil here), and the type of the "parent" owner when a sharing user is uploading.
    @discardableResult
    func uploadServerFile(testAccount:TestAccount = .primaryOwningAccount, mimeType: MimeType = .text, owningAccountType: AccountType? = nil, deviceUUID:String = Foundation.UUID().uuidString, fileUUID:String? = nil, addUser:AddUser = .yes, updatedMasterVersionExpected:Int64? = nil, fileVersion:FileVersionInt = 0, masterVersion:Int64 = 0, cloudFolderName:String? = ServerTestCase.cloudFolderName, appMetaData:AppMetaData? = nil, errorExpected:Bool = false, undelete: Int32 = 0, file: TestFile = .test1, fileGroupUUID:String? = nil, statusCodeExpected: HTTPStatusCode? = nil) -> UploadFileResult? {
    
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
        
        let data:Data!
        
        switch file.contents {
        case .string(let string):
            data = string.data(using: .utf8)!
        case .url(let url):
            data = try? Data(contentsOf: url)
        }

        guard data != nil else {
            return nil
        }
        
        var checkSumType: AccountType
        if let owningAccountType = owningAccountType {
            checkSumType = owningAccountType
        }
        else {
            checkSumType = testAccount.type
        }
        
        let requestCheckSum = file.checkSum(type: checkSumType)
        Log.info("Starting runUploadTest: uploadTextFile: requestCheckSum: \(String(describing: requestCheckSum))")

        let uploadRequest = UploadFileRequest()
        uploadRequest.fileUUID = fileUUIDToSend
        uploadRequest.mimeType = mimeType.rawValue
        uploadRequest.fileVersion = fileVersion
        uploadRequest.masterVersion = masterVersion
        uploadRequest.undeleteServerFile = undelete == 1
        uploadRequest.fileGroupUUID = fileGroupUUID
        uploadRequest.sharingGroupUUID = sharingGroupUUID
        uploadRequest.checkSum = requestCheckSum
        
        uploadRequest.appMetaData = appMetaData
        
        Log.info("Starting runUploadTest: uploadTextFile: uploadRequest: \(String(describing: uploadRequest.toDictionary))")
        
        guard uploadRequest.valid() else {
            XCTFail()
            Log.error("Invalid upload request!")
            return nil
        }
        
        guard runUploadTest(testAccount:testAccount, data:data, uploadRequest:uploadRequest, updatedMasterVersionExpected:updatedMasterVersionExpected, deviceUUID:deviceUUID, errorExpected: errorExpected, statusCodeExpected: statusCodeExpected) else {
            if !errorExpected {
                XCTFail()
            }
            return nil
        }
        
        Log.info("Completed runUploadTest: uploadTextFile")
        
        guard let checkSum = file.checkSum(type: checkSumType) else {
            XCTFail()
            return nil
        }
        
        return UploadFileResult(request: uploadRequest, sharingGroupUUID: sharingGroupUUID, uploadingUserId: uploadingUserId, data: data, checkSum: checkSum)
    }
    
    @discardableResult
    func uploadTextFile(testAccount:TestAccount = .primaryOwningAccount, owningAccountType: AccountType? = nil, deviceUUID:String = Foundation.UUID().uuidString, fileUUID:String? = nil, addUser:AddUser = .yes, updatedMasterVersionExpected:Int64? = nil, fileVersion:FileVersionInt = 0, masterVersion:Int64 = 0, cloudFolderName:String? = ServerTestCase.cloudFolderName, appMetaData:AppMetaData? = nil, errorExpected:Bool = false, undelete: Int32 = 0, stringFile: TestFile = .test1, fileGroupUUID:String? = nil, statusCodeExpected: HTTPStatusCode? = nil) -> UploadFileResult? {
    
        return uploadServerFile(testAccount:testAccount, owningAccountType: owningAccountType, deviceUUID:deviceUUID, fileUUID:fileUUID, addUser:addUser, updatedMasterVersionExpected:updatedMasterVersionExpected, fileVersion:fileVersion, masterVersion:masterVersion, cloudFolderName:cloudFolderName, appMetaData:appMetaData, errorExpected:errorExpected, undelete: undelete, file: stringFile, fileGroupUUID:fileGroupUUID, statusCodeExpected: statusCodeExpected)
    }
    
    // Returns true iff the file could be uploaded.
    @discardableResult
    func runUploadTest(testAccount:TestAccount = .primaryOwningAccount, data:Data, uploadRequest:UploadFileRequest, updatedMasterVersionExpected:Int64? = nil, deviceUUID:String, errorExpected:Bool = false, statusCodeExpected: HTTPStatusCode? = nil) -> Bool {
        
        var result: Bool = true
        
        self.performServerTest(testAccount:testAccount) { expectation, testCreds in
            let headers = self.setupHeaders(testUser: testAccount, accessToken: testCreds.accessToken, deviceUUID:deviceUUID)
            
            // The method for ServerEndpoints.uploadFile really must be a POST to upload the file.
            XCTAssert(ServerEndpoints.uploadFile.method == .post)
            
            Log.debug("uploadRequest.urlParameters(): \(uploadRequest.urlParameters()!)")
            
            self.performRequest(route: ServerEndpoints.uploadFile, responseDictFrom: .header, headers: headers, urlParameters: "?" + uploadRequest.urlParameters()!, body:data) { response, dict in
                
                Log.info("Status code: \(response!.statusCode)")

                if errorExpected {
                    result = false
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
                        result = false
                        expectation.fulfill()
                        return
                    }

                    if let uploadResponse = try? UploadFileResponse.decode(dict!) {
                        if updatedMasterVersionExpected == nil {
                            guard uploadResponse.creationDate != nil, uploadResponse.updateDate != nil else {
                                result = false
                                expectation.fulfill()
                                return
                            }
                        }
                        else {
                            XCTAssert(uploadResponse.masterVersionUpdate == updatedMasterVersionExpected)
                        }
                    }
                    else {
                        result = false
                        XCTFail()
                    }
                }

                expectation.fulfill()
            }
        }
        
        return result
    }
    
    func uploadFileUsingServer(testAccount:TestAccount = .primaryOwningAccount, owningAccountType: AccountType? = nil, deviceUUID:String = Foundation.UUID().uuidString, fileUUID:String = Foundation.UUID().uuidString, mimeType: MimeType = .jpeg, file: TestFile, addUser:AddUser = .yes, fileVersion:FileVersionInt = 0, expectedMasterVersion:MasterVersionInt = 0, appMetaData:AppMetaData? = nil, errorExpected:Bool = false) -> UploadFileResult? {
    
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
        
        var checkSumType: AccountType
        if let owningAccountType = owningAccountType {
            checkSumType = owningAccountType
        }
        else {
            checkSumType = testAccount.type
        }

        let uploadRequest = UploadFileRequest()
        uploadRequest.fileUUID = fileUUID
        uploadRequest.mimeType = mimeType.rawValue
        uploadRequest.fileVersion = fileVersion
        uploadRequest.masterVersion = expectedMasterVersion
        uploadRequest.sharingGroupUUID = sharingGroupUUID
        uploadRequest.checkSum = file.checkSum(type: checkSumType)
        
        guard uploadRequest.valid() else {
            XCTFail()
            return nil
        }
        
        uploadRequest.appMetaData = appMetaData
        
        Log.info("Starting runUploadTest: uploadJPEGFile")
        runUploadTest(testAccount: testAccount, data:data, uploadRequest:uploadRequest, deviceUUID:deviceUUID, errorExpected: errorExpected)
        Log.info("Completed runUploadTest: uploadJPEGFile")
        return UploadFileResult(request: uploadRequest, sharingGroupUUID: sharingGroupUUID, uploadingUserId:uploadingUserId, data: data, checkSum: file.checkSum(type: checkSumType))
    }
    
    func uploadJPEGFile(testAccount:TestAccount = .primaryOwningAccount, owningAccountType: AccountType? = nil, deviceUUID:String = Foundation.UUID().uuidString,
        fileUUID:String = Foundation.UUID().uuidString, addUser:AddUser = .yes, fileVersion:FileVersionInt = 0, expectedMasterVersion:MasterVersionInt = 0, appMetaData:AppMetaData? = nil, errorExpected:Bool = false) -> UploadFileResult? {
        
        let jpegFile = TestFile.catJpg
        return uploadFileUsingServer(testAccount:testAccount, owningAccountType: owningAccountType, deviceUUID:deviceUUID, fileUUID:fileUUID, mimeType: .jpeg, file: jpegFile, addUser:addUser, fileVersion:fileVersion, expectedMasterVersion:expectedMasterVersion, appMetaData:appMetaData, errorExpected:errorExpected)
    }
    
    // sharingGroupName enables you to change the sharing group name during the DoneUploads.
    func sendDoneUploads(testAccount:TestAccount = .primaryOwningAccount, expectedNumberOfUploads:Int32?, deviceUUID:String = Foundation.UUID().uuidString, updatedMasterVersionExpected:Int64? = nil, masterVersion:Int64 = 0, sharingGroupUUID: String, sharingGroupName: String? = nil, failureExpected:Bool = false) {
        
        self.performServerTest(testAccount:testAccount) { expectation, testCreds in
            let headers = self.setupHeaders(testUser: testAccount, accessToken: testCreds.accessToken, deviceUUID:deviceUUID)
            
            let doneUploadsRequest = DoneUploadsRequest()
            doneUploadsRequest.masterVersion = masterVersion
            doneUploadsRequest.sharingGroupUUID = sharingGroupUUID
            
            if let sharingGroupName = sharingGroupName {
                doneUploadsRequest.sharingGroupName = sharingGroupName
            }
            
            self.performRequest(route: ServerEndpoints.doneUploads, headers: headers, urlParameters: "?" + doneUploadsRequest.urlParameters()!, body:nil) { response, dict in
                Log.info("Status code: \(response!.statusCode)")
                
                if failureExpected {
                    XCTAssert(response!.statusCode != .OK, "Worked on doneUploadsRequest request!")
                }
                else {
                    XCTAssert(response!.statusCode == .OK, "Did not work on doneUploadsRequest request")
                    XCTAssert(dict != nil)
                    
                    if let doneUploadsResponse = try? DoneUploadsResponse.decode(dict!) {
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
    
    func getIndex(expectedFiles:[UploadFileRequest]? = nil, deviceUUID:String = Foundation.UUID().uuidString, masterVersionExpected:Int64? = nil, sharingGroupUUID: String? = nil, expectedDeletionState:[String: Bool]? = nil, errorExpected: Bool = false) {
        
        let request = IndexRequest()
        request.sharingGroupUUID = sharingGroupUUID
    
        guard request.valid(),
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

                    if let indexResponse = try? IndexResponse.decode(dict!) {
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
    
    func getIndex(testAccount: TestAccount = .primaryOwningAccount, deviceUUID:String = Foundation.UUID().uuidString, sharingGroupUUID: String? = nil) -> ([FileInfo]?, [SyncServerShared.SharingGroup])? {
        var result:([FileInfo]?, [SyncServerShared.SharingGroup])?
        
        self.performServerTest(testAccount: testAccount) { expectation, creds in
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
                
                guard let indexResponse = try? IndexResponse.decode(dict!) else {
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
    
    func getUploads(expectedFiles:[UploadFileRequest], deviceUUID:String = Foundation.UUID().uuidString, expectedCheckSums: [String: String]? = nil, matchOptionals:Bool = true, expectedDeletionState:[String: Bool]? = nil, sharingGroupUUID: String, errorExpected: Bool = false) {
    
        if expectedCheckSums != nil {
            XCTAssert(expectedFiles.count == expectedCheckSums!.count)
        }
        
        let request = GetUploadsRequest()
        request.sharingGroupUUID = sharingGroupUUID
        
        guard request.valid(),
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
                
                if let getUploadsResponse = try? GetUploadsResponse.decode(dict!) {
                    if getUploadsResponse.uploads == nil {
                        XCTAssert(expectedFiles.count == 0)
                        if expectedCheckSums != nil {
                            XCTAssert(expectedCheckSums!.count == 0)
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

    func createSharingInvitation(testAccount: TestAccount = .primaryOwningAccount, permission: Permission? = nil, numberAcceptors: UInt = 1, allowSharingAcceptance: Bool = true, deviceUUID:String = Foundation.UUID().uuidString, sharingGroupUUID: String, errorExpected: Bool = false, completion:@escaping (_ expectation: XCTestExpectation, _ sharingInvitationUUID:String?)->()) {
        
        self.performServerTest(testAccount: testAccount) { expectation, testCreds in
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
                    completion(expectation, nil)
                }
                else {
                    XCTAssert(response!.statusCode == .OK, "Did not work on request: \(response!.statusCode)")
                    XCTAssert(dict != nil)
                    let response = try? CreateSharingInvitationResponse.decode(dict!)
                    completion(expectation, response?.sharingInvitationUUID)
                }
            }
        }
    }
    
    // This also creates the owning user-- using .primaryOwningAccount
    func createSharingUser(withSharingPermission permission:Permission = .read, sharingUser:TestAccount = .google2, addUser:AddUser = .yes, owningUserWhenCreating:TestAccount = .primaryOwningAccount, numberAcceptors: UInt = 1, allowSharingAcceptance: Bool = true, failureExpected: Bool = false, completion:((_ newSharingUserId:UserId?, _ sharingGroupUUID: String?, _ sharingInvitationUUID:String?)->())? = nil) {
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

        var sharingInvitationUUID:String!
        
        createSharingInvitation(testAccount: owningUserWhenCreating, permission: permission, numberAcceptors: numberAcceptors, allowSharingAcceptance: allowSharingAcceptance, sharingGroupUUID:actualSharingGroupUUID) { expectation, invitationUUID in
            sharingInvitationUUID = invitationUUID
            expectation.fulfill()
        }
        
        redeemSharingInvitation(sharingUser:sharingUser, sharingInvitationUUID: sharingInvitationUUID, errorExpected: failureExpected) { result, expectation in
            if !failureExpected {
                XCTAssert(result?.userId != nil && result?.sharingGroupUUID != nil)
            }
            expectation.fulfill()
        }

        if failureExpected {
            completion?(nil, nil, nil)
        }
        else {
            // Check to make sure we have a new user:
            let userKey = UserRepository.LookupKey.accountTypeInfo(accountType: sharingUser.type, credsId: sharingUser.id())
            let userResults = UserRepository(self.db).lookup(key: userKey, modelInit: User.init)
            guard case .found(let model) = userResults else {
                Log.debug("sharingUser.type: \(sharingUser.type); sharingUser.id(): \(sharingUser.id())")
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
    
    func redeemSharingInvitation(sharingUser:TestAccount, deviceUUID:String = Foundation.UUID().uuidString, canGiveCloudFolderName: Bool = true, sharingInvitationUUID:String? = nil, errorExpected:Bool=false, completion:@escaping (_ result: RedeemSharingInvitationResponse?, _ expectation: XCTestExpectation)->()) {
    
        var actualCloudFolderName: String?
        if sharingUser.type == .Google && canGiveCloudFolderName {
            actualCloudFolderName = ServerTestCase.cloudFolderName
        }

        self.performServerTest(testAccount:sharingUser) { expectation, accountCreds in
            let headers = self.setupHeaders(testUser: sharingUser, accessToken: accountCreds.accessToken, deviceUUID:deviceUUID)
            
            var urlParameters:String?
            
            if sharingInvitationUUID != nil {
                let request = RedeemSharingInvitationRequest()
                request.sharingInvitationUUID = sharingInvitationUUID!
                request.cloudFolderName = actualCloudFolderName
                urlParameters = "?" + request.urlParameters()!
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
                        let redeemSharingInvitationResponse = try? RedeemSharingInvitationResponse.decode(dict) {
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
    
    func getSharingInvitationInfo(sharingInvitationUUID:String? = nil, errorExpected:Bool=false, httpStatusCodeExpected: HTTPStatusCode = .OK, completion:@escaping (_ result: GetSharingInvitationInfoResponse?, _ expectation: XCTestExpectation)->()) {

        self.performServerTest() { expectation in
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
        
        self.performServerTest(testAccount: testAccount) { expectation, account in
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
                    
                    if let uploadDeletionResponse = try? UploadDeletionResponse.decode(dict!) {
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
    func downloadServerFile(testAccount:TestAccount = .primaryOwningAccount, mimeType: MimeType = .text, file: TestFile = .test1, masterVersionExpectedWithDownload:Int, expectUpdatedMasterUpdate:Bool = false, appMetaData:AppMetaData? = nil, uploadFileVersion:FileVersionInt = 0, downloadFileVersion:FileVersionInt = 0, uploadFileRequest:UploadFileRequest? = nil, expectedError: Bool = false, contentsChangedExpected: Bool = false) -> DownloadFileResponse? {
    
        let deviceUUID = Foundation.UUID().uuidString
        let masterVersion:Int64 = 0
        
        var actualUploadFileRequest:UploadFileRequest!
        var actualCheckSum:String!

        let beforeUploadTime = Date()
        var afterUploadTime:Date!
        var fileUUID:String!
        var actualSharingGroupUUID: String!
        
        if uploadFileRequest == nil {
            guard let uploadResult = uploadServerFile(mimeType: mimeType, deviceUUID:deviceUUID, fileVersion:uploadFileVersion, masterVersion:masterVersion, cloudFolderName: ServerTestCase.cloudFolderName, appMetaData:appMetaData, file: file),
                let sharingGroupUUID = uploadResult.sharingGroupUUID else {
                XCTFail()
                return nil
            }
            
            actualSharingGroupUUID = sharingGroupUUID
            
            fileUUID = uploadResult.request.fileUUID
            actualUploadFileRequest = uploadResult.request
            actualCheckSum = uploadResult.checkSum
            self.sendDoneUploads(expectedNumberOfUploads: 1, deviceUUID:deviceUUID, masterVersion: masterVersion, sharingGroupUUID: sharingGroupUUID)
            afterUploadTime = Date()
        }
        else {
            actualUploadFileRequest = uploadFileRequest
            actualCheckSum = uploadFileRequest!.checkSum
            actualSharingGroupUUID = uploadFileRequest!.sharingGroupUUID
        }
        
        var result:DownloadFileResponse?
        
        self.performServerTest(testAccount:testAccount) { expectation, testCreds in
            let headers = self.setupHeaders(testUser:testAccount, accessToken: testCreds.accessToken, deviceUUID:deviceUUID)
            
            let downloadFileRequest = DownloadFileRequest()
            downloadFileRequest.fileUUID = actualUploadFileRequest!.fileUUID
            downloadFileRequest.masterVersion = MasterVersionInt(masterVersionExpectedWithDownload)
            downloadFileRequest.fileVersion = downloadFileVersion
            downloadFileRequest.appMetaDataVersion = appMetaData?.version
            downloadFileRequest.sharingGroupUUID = actualSharingGroupUUID
            
            self.performRequest(route: ServerEndpoints.downloadFile, responseDictFrom:.header, headers: headers, urlParameters: "?" + downloadFileRequest.urlParameters()!, body:nil) { response, dict in
                Log.info("Status code: \(response!.statusCode)")
                
                if expectedError {
                    XCTAssert(response!.statusCode != .OK, "Did not work on failing downloadFileRequest request")
                    XCTAssert(dict == nil)
                }
                else {
                    XCTAssert(response!.statusCode == .OK, "Did not work on downloadFileRequest request")
                    XCTAssert(dict != nil)
                    
                    if let dict = dict,
                        let downloadFileResponse = try? DownloadFileResponse.decode(dict) {
                        result = downloadFileResponse
                        if expectUpdatedMasterUpdate {
                            XCTAssert(downloadFileResponse.masterVersionUpdate != nil)
                        }
                        else {
                            XCTAssert(downloadFileResponse.contentsChanged == contentsChangedExpected)
                            XCTAssert(downloadFileResponse.masterVersionUpdate == nil)
                            XCTAssert(downloadFileResponse.checkSum == actualCheckSum, "downloadFileResponse.checkSum: \(String(describing: downloadFileResponse.checkSum)); actualCheckSum: \(String(describing: actualCheckSum))")
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
    
    @discardableResult
    func downloadTextFile(testAccount:TestAccount = .primaryOwningAccount, masterVersionExpectedWithDownload:Int, expectUpdatedMasterUpdate:Bool = false, appMetaData:AppMetaData? = nil, uploadFileVersion:FileVersionInt = 0, downloadFileVersion:FileVersionInt = 0, uploadFileRequest:UploadFileRequest? = nil, expectedError: Bool = false, contentsChangedExpected: Bool = false) -> DownloadFileResponse? {
    
        return downloadServerFile(testAccount:testAccount, mimeType: .text, file: .test1, masterVersionExpectedWithDownload:masterVersionExpectedWithDownload, expectUpdatedMasterUpdate:expectUpdatedMasterUpdate, appMetaData:appMetaData, uploadFileVersion:uploadFileVersion, downloadFileVersion:downloadFileVersion, uploadFileRequest:uploadFileRequest, expectedError: expectedError, contentsChangedExpected: contentsChangedExpected)
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
    func uploadFile(accountType: AccountType, creds: CloudStorage, deviceUUID:String, testFile: TestFile, uploadRequest:UploadFileRequest, options:CloudStorageFileNameOptions? = nil, nonStandardFileName: String? = nil, failureExpected: Bool = false, errorExpected: CloudStorageError? = nil, expectAccessTokenRevokedOrExpired: Bool = false) -> String? {
    
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
        
        var cloudFileName:String
        if let nonStandardFileName = nonStandardFileName {
            cloudFileName = nonStandardFileName
        }
        else {
            cloudFileName = uploadRequest.cloudFileName(deviceUUID:deviceUUID, mimeType: uploadRequest.mimeType)
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
}

extension ServerTestCase : ConstantsDelegate {
    // A hack to get access to Server.json during testing.
    public func configFilePath(forConstants:Constants) -> String {
        return "/tmp"
    }
}

