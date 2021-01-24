//
//  ServerSetup.swift
//  Server
//
//  Created by Christopher Prince on 12/4/16.
//
//

import LoggerAPI
import Kitura
import KituraNet
import KituraSession
import Credentials
import CredentialsGoogle
import Foundation
import ServerShared
import ServerAccount

/* I'm getting the following error, after having started using SSL and self-signing certificates:
[2017-05-20T21:26:32.218-06:00] [ERROR] [IncomingSocketHandler.swift:148 handleRead()] Read from socket (file descriptor 15) failed. Error = Error code: -9806(0x-264E), ERROR: SSLRead, code: -9806, reason: errSSLClosedAbort.
See also: https://github.com/IBM-Swift/Kitura-net/issues/196
*/

public typealias ProcessRequest = (RequestProcessingParameters)->()

class RequestHandler {
    typealias PostRequestRunner = () throws -> ()
    
    private var request:RouterRequest!
    private var response:RouterResponse!
    
    private var repositories:Repositories!
    private var authenticationLevel:AuthenticationLevel!
    private var currentSignedInUser:User?
    private var deviceUUID:String?
    private var endpoint:ServerEndpoint!
    private let services: Services

    init(request:RouterRequest, response:RouterResponse, services: Services, endpoint:ServerEndpoint? = nil) {
        self.request = request
        self.response = response
        if endpoint == nil {
            self.authenticationLevel = .secondary
        }
        else {
            self.authenticationLevel = endpoint!.authenticationLevel
        }
        self.endpoint = endpoint
        self.services = services
        ServerStatsKeeper.session.increment(stat: .apiRequestsCreated)
        
        Log.info("RequestHandler.init: numberCreated: \(ServerStatsKeeper.session.currentValue(stat: .apiRequestsCreated)); numberDeleted: \(ServerStatsKeeper.session.currentValue(stat: .apiRequestsDeleted));")
    }
    
    deinit {
        ServerStatsKeeper.session.increment(stat: .apiRequestsDeleted)
        Log.info("RequestHandler.deinit: numberCreated: \(ServerStatsKeeper.session.currentValue(stat: .apiRequestsCreated)); numberDeleted: \(ServerStatsKeeper.session.currentValue(stat: .apiRequestsDeleted));")
    }
    
    public func failWithError(message: String, statusCode:HTTPStatusCode = .internalServerError) {
        failWithError(failureResult: .messageWithStatus(message, statusCode))
    }

    public func failWithError(failureResult: FailureResult) {
        setJsonResponseHeaders()
        
        let code: HTTPStatusCode
        var result: [String: Any]
        let errorKey = "error"
        let goneReasonKey = "goneReason"

        switch failureResult {
        case .message(let message):
            Log.error(message)
            code = .internalServerError
            result = [
                errorKey: message
            ]
        
        case .messageWithStatus(let message, let statusCode):
            Log.error(message)
            code = statusCode
            result = [
                errorKey: message
            ]
            
        case .goneWithReason(message: let message, let goneReason):
            Log.warning("Gone: \(goneReason); message: \(message)")
            code = .gone
            result = [
                errorKey: message,
                goneReasonKey: goneReason.rawValue
            ]
        }

        self.response.statusCode = code
        
        self.endWith(clientResponse: .jsonDict(result))
    }
    
    enum EndWithResponse {
    case jsonDict([String: Any])
    case jsonString(String)
    case data(data:Data?, headers:[String:String])
    case headers([String:String])
    }
    
    private func endWith(clientResponse:EndWithResponse) {
        self.response.headers.append(ServerConstants.httpResponseCurrentServerVersion, value: Configuration.misc.deployedGitTag)
        if let minIOSClientVersion = Configuration.server.iOSMinimumClientVersion {
            self.response.headers.append(
                ServerConstants.httpResponseMinimumIOSClientAppVersion, value: minIOSClientVersion)
        }
        
        switch clientResponse {
        case .jsonString(let jsonString):
            self.response.send(jsonString)
            
        case .jsonDict(let jsonDict):
            if let jsonString = JSONExtras.toJSONString(dict: jsonDict) {
                self.response.send(jsonString)
            }
            else {
                let message = "Failed on json encode for jsonDict: \(jsonDict)"
                Log.error(message)
                self.response.statusCode = HTTPStatusCode.internalServerError
                self.response.send(message)
            }
            
        case .data(data: let data, headers: let headers):
            for (key, value) in headers {
                self.response.headers.append(key, value: value)
            }
            
            if data != nil {
                self.response.send(data: data!)
            }
            
        case .headers(let headers):
            for (key, value) in headers {
                self.response.headers.append(key, value: value)
            }
        }
        
        Log.info("REQUEST \(request.urlURL.path): ABOUT TO END ...")

        do {
            try self.response.end()
            Log.info("REQUEST \(request.urlURL.path): STATUS CODE: \(response.statusCode)")
        } catch (let error) {
            Log.error("Failed on `end` in endWith: \(error.localizedDescription); HTTP status code: \(response.statusCode)")
        }
        
        Log.info("REQUEST \(request.urlURL.path): COMPLETED")
    }
    
    func setJsonResponseHeaders() {
        self.response.headers["Content-Type"] = "application/json"
    }
    
    enum SuccessResult {
        case jsonString(String)
        case dataWithHeaders(Data?, headers:[String:String])
        case headers([String:String])
        case nothing
    }
    
    enum FailureResult {
        case message(String)
        case messageWithStatus(String, HTTPStatusCode)
        case goneWithReason(message: String, GoneReason)
    }
    
    enum ServerResult {
        case success(SuccessResult, runner: RequestHandler.PostRequestRunner?)
        case failure(FailureResult)
    }
    
    enum PermissionsResult {
        case success(sharingGroupUUID: String?)
        case failure
    }
    
    func handlePermissionsAndLocking(requestObject:RequestMessage) -> PermissionsResult {
        if let sharing = endpoint.sharing {
            // Endpoint uses sharing group. Must give sharingGroupUUID in request.
            
            guard let dict = requestObject.toDictionary, let sharingGroupUUID = dict[ServerEndpoint.sharingGroupUUIDKey] as? String else {
            
                self.failWithError(message: "Could not get sharing group uuid from request that uses sharing group: \(String(describing: requestObject.toDictionary))")
                return .failure
            }
            
            // The user is on the system. Whether or not they can perform the endpoint depends on their permissions for the sharing group.
            let key = SharingGroupUserRepository.LookupKey.primaryKeys(sharingGroupUUID: sharingGroupUUID, userId: currentSignedInUser!.userId)
            let result = repositories.sharingGroupUser.lookup(key: key, modelInit: SharingGroupUser.init)
            switch result {
            case .found(let model):
                let sharingGroupUser = model as! SharingGroupUser
                guard let userPermissions = sharingGroupUser.permission else {
                    self.failWithError(message: "SharingGroupUser did not have permissions!")
                    return .failure
                }
                
                if let minPermission = sharing.minPermission {
                    guard userPermissions.hasMinimumPermission(minPermission) else {
                        self.failWithError(message: "User did not meet minimum permissions -- needed: \(minPermission); had: \(userPermissions)!")
                        return .failure
                    }
                }
                
            case .noObjectFound:
                // One reason that the sharing group user might not be found is that the SharingGroupUser was removed from the system-- e.g., if an owning user is deleted, SharingGroupUser rows that have it as their owningUserId will be removed.
                // If a client fails with this error, it seems like some kind of client error or edge case where the client should have been updated already (i.e., from an Index endpoint call) so that it doesn't make such a request. Therefore, I'm not going to code a special case on the client to deal with this.
                // 7/8/20; Actually, this occurs simply when an incorrect sharingGroupUUID is used when uploading a file. Let's test to see if the sharingGroupUUID exists.
                if let exists = sharingGroupExists(sharingGroupUUID: sharingGroupUUID), exists {
                    self.failWithError(failureResult:
                        .goneWithReason(message: "SharingGroupUser object not found!", .userRemoved))
                }
                else {
                    self.failWithError(failureResult:
                        .message("sharingGroupUUID not found!"))
                }
                        
                return .failure
            case .error(let error):
                self.failWithError(message: error)
                return .failure
            }
            
            return .success(sharingGroupUUID: sharingGroupUUID)
        }
        
        return .success(sharingGroupUUID: nil)
    }
    
    private func sharingGroupExists(sharingGroupUUID: String) -> Bool? {
        let key = SharingGroupRepository.LookupKey.sharingGroupUUID(sharingGroupUUID)
        let result = repositories.sharingGroup.lookup(key: key, modelInit: SharingGroup.init)
        switch result {
        case .found:
            return true
        case .noObjectFound:
            return false
        case .error(let error):
            Log.error("sharingGroupExists: \(error)")
            return nil
        }
    }
    
    // Starts a transaction, and calls the `dbOperations` closure. If the closure succeeds (no error), then commits the transaction. Otherwise, rolls it back.
    private func dbTransaction(_ db:Database, handleResult:@escaping (ServerResult) ->(), dbOperations:(_ callback: @escaping (ServerResult) ->())->()) {

        // 6/24/19; While I used to, I'm no longer including this in the transaction. This is because I can get a deadlock just on the insert of a record into the DeviceUUID table. The consequence of not including it in the transaction may include creating a db record even though the rest of the request fails. No biggie. Presumably the device would have made another successful request and the device record would get created in any event. Why not creat it now?
        if case .error(let errorMessage) = checkDeviceUUID() {
            handleResult(.failure(.message("Failed checkDeviceUUID: \(errorMessage)")))
            return
        }
        
        if !db.startTransaction() {
            handleResult(.failure(.message("Could not start a transaction!")))
            return
        }
        
        func dbTransactionHandleResult(_ result: ServerResult) {
            switch result {
            case .success:
                if !db.commit() {
                    let message = "Error during COMMIT operation!"
                    Log.error(message)
                    handleResult(.failure(.message(message)))
                    return
                }
                
            case .failure:
                if !db.rollback() {
                    let message = "Error during ROLLBACK operation!"
                    Log.error(message)
                    handleResult(.failure(.message(message)))
                    return
                }
            }
            
            handleResult(result)
        }
        
        dbOperations(dbTransactionHandleResult)
    }
    
    func doRequest(createRequest: @escaping (RouterRequest) -> RequestMessage?,
        processRequest: @escaping ProcessRequest) {
        
        setJsonResponseHeaders()
        let profile = request.userProfile
#if DEBUG
//        for header in request.headers {
//            Log.info("request.header: \(header)")
//        }
#endif
        self.deviceUUID = request.headers[ServerConstants.httpRequestDeviceUUID]
        
#if DEBUG
        if let profile = profile {
            let userId = profile.id
            let userName = profile.displayName
            Log.info("Profile: \(String(describing: profile)); userId: \(userId); userName: \(userName)")
        }
#endif

        // Establishing a database connection per request.
        guard let db = Database() else {
            let message = "Could not open database connection for request."
            Log.error(message)
            failWithError(message: message)
            return
        }
        
        repositories = Repositories(db: db)
        let accountDelegate = UserRepository.AccountDelegateHandler(userRepository: repositories.user, accountManager: services.accountManager)
        
        var accountProperties: AccountProperties?
        
        switch authenticationLevel! {
        case .none:
            break
            
        case .primary, .secondary:
            // Only do this if we are requiring primary or secondary authorization-- this gets account specific properties from the request, assuming we are using authorization.
            do {
                accountProperties = try services.accountManager.getProperties(fromRequest: request)
            } catch (let error) {
                let message = "YIKES: could not get account properties from request: \(error)"
                Log.error(message)
                failWithError(message: message)
                return
            }
        }

        var dbCreds:Account?
        
        guard let requestObject = createRequest(request) else {
            self.failWithError(message: "Could not create request object from RouterRequest: \(String(describing: request))")
            return
        }
    
        var sharingGroupUUID: String?

        if authenticationLevel! == .secondary {
            // We have .secondary authentication-- i.e., we should have the user recorded in the database already.
            
            guard let accountProperties = accountProperties else {
                self.failWithError(message: "Could not get accountProperties.")
                return
            }
            
            let key = UserRepository.LookupKey.accountTypeInfo(accountType:accountProperties.accountScheme.accountName, credsId: profile!.id)
            let userLookup = self.repositories.user.lookup(key: key, modelInit: User.init)
            
            switch userLookup {
            case .found(let model):
                currentSignedInUser = (model as? User)!
                var errorString:String?
                
                do {
                    dbCreds = try services.accountManager.accountFromJSON(currentSignedInUser!.creds, accountName: currentSignedInUser!.accountType, user: .user(currentSignedInUser!), accountDelegate: accountDelegate)
                } catch (let error) {
                    errorString = "\(error)"  
                }
                
                if errorString != nil || dbCreds == nil {
                    self.failWithError(message: "Could not convert Creds of type: \(String(describing: currentSignedInUser!.accountType)) from JSON: \(String(describing: currentSignedInUser!.creds)); error: \(String(describing: errorString))")
                    return
                }
                
                let result = handlePermissionsAndLocking(requestObject: requestObject)
                switch result {
                case .failure:
                    return
                    
                case .success(sharingGroupUUID: let sgid):
                    sharingGroupUUID = sgid
                }
                
            case .noObjectFound:
                Log.error("User lookup key: \(key)")
                failWithError(message: "Failed on secondary authentication", statusCode: .unauthorized)
                return
                
            case .error(let error):
                failWithError(message: "Failed looking up user: \(key): \(error)", statusCode: .internalServerError)
                return
            }
        }
                
#if DEBUG
        // Failure testing.
        if request.headers[ServerConstants.httpRequestEndpointFailureTestKey] != nil {
            self.failWithError(message: "Failure test requested by client.")
            return
        }
#endif
        
        // 6/1/17; Up until this point, I had been (a) calling .end on the RouterResponse object, and (b) only after that committing the transaction (or rolling it back) on the database. However, that can generate some unwanted asynchronous processing. i.e., the network caller can potentially initiate another request *before* the database commit completes. Instead, I should be: (a) committing (or rolling back) the transaction, and then (b) calling .end. That should provide the synchronous character that I really want.
        
        if profile == nil {
            assert(authenticationLevel! == .none)
            
            dbTransaction(db, handleResult: handleTransactionResult) { [weak self] handleResult in
                guard let self = self else { return }
                self.doRemainingRequestProcessing(dbCreds: nil, profileCreds:nil, requestObject: requestObject, db: db, profile: nil, accountProperties: nil, sharingGroupUUID: sharingGroupUUID, accountDelegate: accountDelegate, processRequest: processRequest, handleResult: handleResult)
            }
        }
        else {
            var credsUser:AccountCreationUser?
            switch authenticationLevel! {
            case .primary:
                // We don't have a userId yet for this user.
                break
                
            case .secondary:
                credsUser = .user(self.currentSignedInUser!)
                
            case .none:
                assertionFailure("Should never get here with authenticationLevel == .none!")
            }
            
            guard let accountProperties = accountProperties else {
                self.failWithError(message: "Do not have AccountProperties!s")
                return
            }
            
            if let profileCreds = services.accountManager.accountFromProperties(properties: accountProperties, user: credsUser, accountDelegate: accountDelegate) {
            
                dbTransaction(db, handleResult: handleTransactionResult) { [weak self] handleResult in
                    guard let self = self else { return }
                    self.doRemainingRequestProcessing(dbCreds:dbCreds, profileCreds:profileCreds, requestObject: requestObject, db: db, profile: profile, accountProperties: accountProperties, sharingGroupUUID: sharingGroupUUID, accountDelegate: accountDelegate, processRequest: processRequest, handleResult: handleResult)
                }
            }
            else {
                handleTransactionResult(.failure(.messageWithStatus("Failed converting to Creds from profile", .unauthorized)))
            }
        }
    }
    
    private func handleTransactionResult(_ result:ServerResult) {
        var postRequestRunner: RequestHandler.PostRequestRunner?
        
        // `endWith` and `failWithError` call the `RouterResponse` `end` method, and thus we have waited until the very end of processing of the request to finish and return control back to the caller.
        switch result {
        case .success(.jsonString(let jsonString), let runner):
            postRequestRunner = runner
            endWith(clientResponse: .jsonString(jsonString))
            
        case .success(.dataWithHeaders(let data, headers: let headers), let runner):
            postRequestRunner = runner
            endWith(clientResponse: .data(data: data, headers: headers))
        
        case .success(.headers(let headers), let runner):
            postRequestRunner = runner
            endWith(clientResponse: .headers(headers))
        
        case .success(.nothing, let runner):
            postRequestRunner = runner
            endWith(clientResponse: .jsonDict([:]))
            
        case .failure(let failureResult):
            failWithError(failureResult: failureResult)
        }
        
        do {
            try postRequestRunner?()
        } catch let error {
            Log.error("Post commit runner: \(error)")
        }
    }
    
    private func doRemainingRequestProcessing(dbCreds:Account?, profileCreds:Account?, requestObject:RequestMessage, db: Database, profile: UserProfile?, accountProperties: AccountProperties?, sharingGroupUUID: String?, accountDelegate: AccountDelegate, processRequest: @escaping ProcessRequest, handleResult:@escaping (ServerResult) ->()) {
        
        var effectiveOwningUserCreds:Account?
        
        // For secondary authentication, we'll have a current signed in user.
        // Not treating a nil effectiveOwningUserId for the same reason as the `.noObjectFound` case below.
        
        if let user = currentSignedInUser, let sharingGroupUUID = sharingGroupUUID,
            case .found(let effectiveOwningUserId) = Controllers.getEffectiveOwningUserId(user: user, sharingGroupUUID: sharingGroupUUID, sharingGroupUserRepo: repositories.sharingGroupUser) {

            let effectiveOwningUserKey = UserRepository.LookupKey.userId(effectiveOwningUserId)
            Log.debug("effectiveOwningUserId: \(effectiveOwningUserId)")
            
            let userResults = repositories.user.lookup(key: effectiveOwningUserKey, modelInit: User.init)
            switch userResults {
            case .found(let model):
                guard let effectiveOwningUser = model as? User else {
                    handleResult(.failure(.message("Could not convert effective owning user model to User.")))
                    return
                }
                
                effectiveOwningUserCreds = try? services.accountManager.accountFromJSON(effectiveOwningUser.creds, accountName: effectiveOwningUser.accountType, user: .user(effectiveOwningUser), accountDelegate: accountDelegate)
                
                guard effectiveOwningUserCreds != nil else {
                    handleResult(.failure(.message("Could not get effective owning user creds.")))
                    return
                }
                
            case .noObjectFound:
                // Not treating this as an error. Downstream from this, where needed, we check to see if effectiveOwningUserCreds is nil. See also [1] in Controllers.swift.
                Log.warning("No object found when trying to populate effectiveOwningUserCreds")

            case .error(let error):
                handleResult(.failure(.message(error)))
                return
            }
        }
        
        let params = RequestProcessingParameters(request: requestObject, ep:endpoint, creds: dbCreds, effectiveOwningUserCreds: effectiveOwningUserCreds, profileCreds: profileCreds, userProfile: profile, accountProperties: accountProperties, currentSignedInUser: currentSignedInUser, db:db, repos:repositories, routerResponse:response, deviceUUID: deviceUUID, services: services, accountDelegate: accountDelegate) { response in
        
            var message:ResponseMessage!
            var postCommitRunner: RequestHandler.PostRequestRunner?
            
            switch response {
            case .success(let responseMessage):
                message = responseMessage
                
            case .successWithRunner(let responseMessage, runner: let runner):
                message = responseMessage
                postCommitRunner = runner
                
            case .failure(let failureResult):
                if let failureResult = failureResult {
                    handleResult(.failure(failureResult))
                }
                else {
                    handleResult(.failure(.message("Could not create response object from request object")))
                }
                
                return
            }

            guard let jsonString = message.jsonString else {
                handleResult(.failure(.message("Could not convert response message to a JSON string")))
                return
            }
            
            switch message.responseType {
            case .json:
                handleResult(.success(.jsonString(jsonString), runner: postCommitRunner))

            case .data(let data):
                handleResult(.success(.dataWithHeaders(data, headers:[ServerConstants.httpResponseMessageParams:jsonString]), runner: postCommitRunner))
                
            case .header:
                handleResult(.success(.headers(
                    [ServerConstants.httpResponseMessageParams:jsonString]), runner: postCommitRunner))
            }
        } // end: let params = RequestProcessingParameters

        // 7/16/17; Until today I had another large bug that was undetected. I was calling `processRequest` below assuming that request processing was being done *synchronously*, which was blatently untrue! This was causing `end` to be called for some requests prematurely. I've now made changes to use callbacks, and deal with the fact that asynchronous request processing is happening in many cases.

        processRequest(params)
    }
    
    // MARK: AccountDelegate

    enum CheckDeviceUUIDResult {
        case success
        case uuidNotNeeded
        case error(message: String)
    }
    
    private func checkDeviceUUID() -> CheckDeviceUUIDResult {
        switch authenticationLevel! {
        case .none:
            return .uuidNotNeeded
            
        case .primary, .secondary:
            if self.deviceUUID == nil {
                return .error(message: "Did not provide a Device UUID with header \(ServerConstants.httpRequestDeviceUUID)")
            }
            else if currentSignedInUser == nil && authenticationLevel == .primary {
                // If we don't have a signed in user, we can't search for existing deviceUUID's. But that's not an error.
                return .success
            }
            else {
                let key = DeviceUUIDRepository.LookupKey.deviceUUID(self.deviceUUID!)
                let result = repositories.deviceUUID.lookup(key: key, modelInit: DeviceUUID.init)
                switch result {
                case .error(let error):
                    return .error(message: "Error looking up device UUID: \(error)")
                    
                case .found(_):
                    return .success
                    
                case .noObjectFound:
                    let newDeviceUUID = DeviceUUID(userId: currentSignedInUser!.userId, deviceUUID: self.deviceUUID!)
                    let addResult = repositories.deviceUUID.add(deviceUUID: newDeviceUUID)
                    switch addResult {
                    case .error(let error):
                        return .error(message: "Error adding new device UUID: \(error)")
                        
                    case .exceededMaximumUUIDsPerUser:
                        return .error(message: "Exceeded maximum UUIDs per user: \(String(describing: repositories.deviceUUID.maximumNumberOfDeviceUUIDsPerUser))")
                        
                    case .success:
                        return .success
                    }
                }
            }
        }
    }
}
