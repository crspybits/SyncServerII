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
//import Gloss
import KituraSession
import Credentials
import CredentialsGoogle
import Foundation
import SyncServerShared

/* I'm getting the following error, after having started using SSL and self-signing certificates:
[2017-05-20T21:26:32.218-06:00] [ERROR] [IncomingSocketHandler.swift:148 handleRead()] Read from socket (file descriptor 15) failed. Error = Error code: -9806(0x-264E), ERROR: SSLRead, code: -9806, reason: errSSLClosedAbort.
See also: https://github.com/IBM-Swift/Kitura-net/issues/196
*/

public typealias ProcessRequest = (RequestProcessingParameters)->()

class RequestHandler : AccountDelegate {
    private var request:RouterRequest!
    private var response:RouterResponse!
    
    private var repositories:Repositories!
    private var authenticationLevel:AuthenticationLevel!
    private var currentSignedInUser:User?
    private var deviceUUID:String?
    private var endpoint:ServerEndpoint!
    
    init(request:RouterRequest, response:RouterResponse, endpoint:ServerEndpoint? = nil) {
        self.request = request
        self.response = response
        if endpoint == nil {
            self.authenticationLevel = .secondary
        }
        else {
            self.authenticationLevel = endpoint!.authenticationLevel
        }
        self.endpoint = endpoint
        ServerStatsKeeper.session.increment(stat: .apiRequestsCreated)
        
        Log.info("RequestHandler.init: numberCreated: \(ServerStatsKeeper.session.currentValue(stat: .apiRequestsCreated)); numberDeleted: \(ServerStatsKeeper.session.currentValue(stat: .apiRequestsDeleted));")
    }
    
    deinit {
        ServerStatsKeeper.session.increment(stat: .apiRequestsDeleted)
        Log.info("RequestHandler.deinit: numberCreated: \(ServerStatsKeeper.session.currentValue(stat: .apiRequestsCreated)); numberDeleted: \(ServerStatsKeeper.session.currentValue(stat: .apiRequestsDeleted));")
    }

    public func failWithError(message:String, statusCode:HTTPStatusCode = .internalServerError) {
        
        setJsonResponseHeaders()
        Log.error(message)

        self.response.statusCode = statusCode
        
        let result = [
            "error" : message
        ]
        self.endWith(clientResponse: .json(result))
    }
    
    enum EndWithResponse {
    case json([String: Any])
    case data(data:Data?, headers:[String:String])
    case headers([String:String])
    }
    
    private func endWith(clientResponse:EndWithResponse) {
        self.response.headers.append(ServerConstants.httpResponseCurrentServerVersion, value: Constants.session.deployedGitTag)
        
        switch clientResponse {
        case .json(let jsonDict):
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
        case json([String: Any])
        case dataWithHeaders(Data?, headers:[String:String])
        case headers([String:String])
        case nothing
    }
    
    enum FailureResult {
        case message(String)
        case messageWithStatus(String, HTTPStatusCode)
    }
    
    enum ServerResult {
        case success(SuccessResult)
        case failure(FailureResult)
    }
    
    enum PermissionsAndLockingResult {
        case success(lockedSharingGroup: SharingGroupId?)
        case failure
    }
    
    func handlePermissionsAndLocking(requestObject:RequestMessage) -> PermissionsAndLockingResult {
        if let sharing = endpoint.sharing {
            // Endpoint uses sharing group. Must give sharingGroupId in request.
            guard let dict = requestObject.toJSON(), let sharingGroupId = dict[ServerEndpoint.sharingGroupIdKey] as? SharingGroupId else {
            
                self.failWithError(message: "Could not get sharing group id from request that uses sharing group: \(String(describing: requestObject.toJSON()))")
                return .failure
            }
            
            // The user is on the system. Whether or not they can perform the endpoint depends on their permissions for the sharing group.
            let key = SharingGroupUserRepository.LookupKey.primaryKeys(sharingGroupId: sharingGroupId, userId: currentSignedInUser!.userId)
            let result = repositories.sharingGroupUser.lookup(key: key, modelInit: SharingGroupUser.init)
            switch result {
            case .found(let model):
                let sharingGroupUser = model as! SharingGroupUser
                guard let userPermissions = sharingGroupUser.permission else {
                    self.failWithError(message: "SharingGroupUser did not have permissions!")
                    return .failure
                }
                
                guard userPermissions.hasMinimumPermission(sharing.minPermission) else {
                    self.failWithError(message: "User did not meet minimum permissions -- needed: \(sharing.minPermission); had: \(userPermissions)!")
                    return .failure
                }
                
            case .noObjectFound:
                self.failWithError(message: "SharingGroupUser object not found!")
                return .failure
            case .error(let error):
                self.failWithError(message: error)
                return .failure
            }
            
            if sharing.needsLock {
                let lock = Lock(sharingGroupId: sharingGroupId, deviceUUID:deviceUUID!)
                switch repositories.lock.lock(lock: lock) {
                case .success:
                    return .success(lockedSharingGroup: sharingGroupId)
                
                // 2/11/16. We should never get here. With the transaction support just added, when server thread/request X attempts to obtain a lock and (a) another server thread/request (Y) has previously started a transaction, and (b) has obtained a lock in this manner, but (c) not ended the transaction, (d) a *transaction-level* lock will be obtained on the lock table row by request Y. Request X will be *blocked* in the server until the request Y completes its transaction.
                case .lockAlreadyHeld:
                    self.failWithError(message: "Could not obtain lock!!")
                    return .failure
                
                case .errorRemovingStaleLocks, .modelValueWasNil, .otherError:
                    self.failWithError(message: "Error obtaining lock!")
                    return .failure
                }
            }
        }
        
        return .success(lockedSharingGroup: nil)
    }
    
    // Starts a transaction, and calls the `dbOperations` closure. If the closure succeeds (no error), then commits the transaction. Otherwise, rolls it back.
    private func dbTransaction(_ db:Database, handleResult:@escaping (ServerResult) ->(), dbOperations:(_ callback: @escaping (ServerResult) ->())->()) {
    
        if !db.startTransaction() {
            handleResult(.failure(.message("Could not start a transaction!")))
            return
        }
        
        // Waiting until this point to call `checkDeviceUUID` because it may create a db record.
        if case .error(let errorMessage) = checkDeviceUUID() {
            _ = db.rollback()
            handleResult(.failure(.message("Failed checkDeviceUUID: \(errorMessage)")))
            return
        }

        func dbTransactionHandleResult(_ result: ServerResult) {
            switch result {
            case .success(_):
                if !db.commit() {
                    let message = "Error during COMMIT operation!"
                    Log.error(message)
                    handleResult(.failure(.message(message)))
                    return
                }
                
            case .failure(_):
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
        self.deviceUUID = request.headers[ServerConstants.httpRequestDeviceUUID]
        Log.info("self.deviceUUID: \(String(describing: self.deviceUUID))")
        
#if DEBUG
        if profile != nil {
            let userId = profile!.id
            let userName = profile!.displayName
            Log.info("Profile: \(String(describing: profile)); userId: \(userId); userName: \(userName)")
        }
#endif

        let db = Database()
        repositories = Repositories(db: db)
        
        switch authenticationLevel! {
        case .none:
            break
            
        case .primary, .secondary:
            if profile == nil {
                // We should really never get here. Credentials security check should make sure of that. This is a double check.
                let message = "YIKES: Should have had a user profile!"
                Log.error(message)
                failWithError(message: message)
                return
            }
            
            // Only do this if we are requiring primary or secondary authorization-- this updates the profile from the request, assuming we are using authorization.
            do {
                try AccountManager.session.updateUserProfile(profile!, fromRequest: request)
            } catch (let error) {
                let message = "YIKES: Non-nil UserProfile, but could not do profile update: \(error)"
                Log.error(message)
                failWithError(message: message)
                return
            }
        }

        var dbCreds:Account?
        
        guard let requestObject = createRequest(request) else {
            self.failWithError(message: "Could not create request object from RouterRequest: \(request)")
            return
        }
    
        var lockedSharingGroup: SharingGroupId?
        
        if authenticationLevel! == .secondary {
            // We have .secondary authentication-- i.e., we should have the user recorded in the database already.
            
            guard let accountType = AccountType.for(userProfile: profile!) else {
                self.failWithError(message: "Could not get accountType.")
                return
            }
            
            let key = UserRepository.LookupKey.accountTypeInfo(accountType:accountType, credsId: profile!.id)
            let userLookup = self.repositories.user.lookup(key: key, modelInit: User.init)
            
            switch userLookup {
            case .found(let model):
                currentSignedInUser = (model as? User)!
                var errorString:String?
                
                do {
                    dbCreds = try AccountManager.session.accountFromJSON(currentSignedInUser!.creds, accountType: currentSignedInUser!.accountType, user: .user(currentSignedInUser!), delegate: self)
                } catch (let error) {
                    errorString = "\(error)"  
                }
                
                if errorString != nil || dbCreds == nil {
                    self.failWithError(message: "Could not convert Creds of type: \(currentSignedInUser!.accountType) from JSON: \(currentSignedInUser!.creds); error: \(String(describing: errorString))")
                    return
                }
                
                let result = handlePermissionsAndLocking(requestObject: requestObject)
                switch result {
                case .failure:
                    return
                case .success(lockedSharingGroup: let sharingGroupId):
                    lockedSharingGroup = sharingGroupId
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
        
        Log.debug("requestObject: \(String(describing: requestObject.toJSON()))")
        
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
            
            dbTransaction(db, handleResult: handleTransactionResult) { handleResult in
                doRemainingRequestProcessing(dbCreds: nil, profileCreds:nil, requestObject: requestObject, db: db, profile: nil, lockedSharingGroup: lockedSharingGroup, processRequest: processRequest, handleResult: handleResult)
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
            
            if let profileCreds = AccountManager.session.accountFromProfile(profile: profile!, user: credsUser, delegate: self) {
            
                dbTransaction(db, handleResult: handleTransactionResult) { handleResult in
                    doRemainingRequestProcessing(dbCreds:dbCreds, profileCreds:profileCreds, requestObject: requestObject, db: db, profile: profile, lockedSharingGroup: lockedSharingGroup, processRequest: processRequest, handleResult: handleResult)
                }
            }
            else {
                handleTransactionResult(.failure(.messageWithStatus("Failed converting to Creds from profile", .unauthorized)))
            }
        }
    }
    
    private func handleTransactionResult(_ result:ServerResult) {
        // `endWith` and `failWithError` call the `RouterResponse` `end` method, and thus we have waited until the very end of processing of the request to finish and return control back to the caller.
        switch result {
        case .success(.json(let json)):
            endWith(clientResponse: .json(json))
        
        case .success(.dataWithHeaders(let data, headers: let headers)):
            endWith(clientResponse: .data(data: data, headers: headers))
        
        case .success(.headers(let headers)):
            endWith(clientResponse: .headers(headers))
        
        case .success(.nothing):
            endWith(clientResponse: .json([:]))
            
        case .failure(.message(let message)):
            failWithError(message: message)
        
        case .failure(.messageWithStatus(let message, let statusCode)):
            failWithError(message: message, statusCode: statusCode)
        }
    }
    
    private func doRemainingRequestProcessing(dbCreds:Account?, profileCreds:Account?, requestObject:RequestMessage, db: Database, profile: UserProfile?, lockedSharingGroup: SharingGroupId?, processRequest: @escaping ProcessRequest, handleResult:@escaping (ServerResult) ->()) {
        
        var effectiveOwningUserCreds:Account?
        
        // For secondary authentication, we'll have a current signed in user.
        // Not treating a nil effectiveOwningUserId for the same reason as the `.noObjectFound` case below.
        if let effectiveOwningUserId = currentSignedInUser?.effectiveOwningUserId {
            let effectiveOwningUserKey = UserRepository.LookupKey.userId(effectiveOwningUserId)
            Log.debug("effectiveOwningUserId: \(effectiveOwningUserId)")
            let userResults = UserRepository(db).lookup(key: effectiveOwningUserKey, modelInit: User.init)
            switch userResults {
            case .found(let model):
                guard let effectiveOwningUser = model as? User else {
                    handleResult(.failure(.message("Could not convert effective owning user model to User.")))
                    return
                }
                
                effectiveOwningUserCreds = effectiveOwningUser.credsObject
                guard effectiveOwningUserCreds != nil else {
                    handleResult(.failure(.message("Could not get effective owning user creds.")))
                    return
                }
                
                effectiveOwningUserCreds!.delegate = self

            case .noObjectFound:
                // Not treating this as an error. Downstream from this, where needed, we check to see if effectiveOwningUserCreds is nil. See also [1] in Controllers.swift.
                Log.warning("No object found when trying to populate effectiveOwningUserCreds")

            case .error(let error):
                handleResult(.failure(.message(error)))
                return
            }
        }
        
        let params = RequestProcessingParameters(request: requestObject, ep:endpoint, creds: dbCreds, effectiveOwningUserCreds: effectiveOwningUserCreds, profileCreds: profileCreds, userProfile: profile, currentSignedInUser: currentSignedInUser, db:db, repos:repositories, routerResponse:response, deviceUUID: deviceUUID) { response in
        
            // If we locked before, do unlock now.
            if let sharingGroupId = lockedSharingGroup {
                _ = self.repositories.lock.unlock(sharingGroupId: sharingGroupId)
            }
        
            var message:ResponseMessage!
            
            switch response {
            case .success(let responseMessage):
                message = responseMessage
                
            case .failure(let failureResult):
                if let failureResult = failureResult {
                    handleResult(.failure(failureResult))
                }
                else {
                    handleResult(.failure(.message("Could not create response object from request object")))
                }
                
                return
            }

            let jsonDict = message.toJSON()
            if nil == jsonDict {
                handleResult(.failure(.message("Could not convert response object to json dictionary")))
                return
            }
            
            func getJSONString() -> String? {
                var result:String?
                
                do {
                    result = try jsonDict!.jsonEncodedString()
                } catch (let error) {
                    handleResult(.failure(.message("Could not convert json dict to string: \(error)")))
                }
                
                return result
            }
            
            switch message.responseType {
            case .json:
                handleResult(.success(.json(jsonDict!)))

            case .data(let data):
                if let jsonString = getJSONString() {
                    handleResult(.success(.dataWithHeaders(data, headers:[ServerConstants.httpResponseMessageParams:jsonString])))
                }
                
            case .header:
                if let jsonString = getJSONString() {
                    handleResult(.success(.headers(
                        [ServerConstants.httpResponseMessageParams:jsonString])))
                }
            }
        }

        // 7/16/17; Until today I had another large bug that was undetected. I was calling `processRequest` below assuming that request processing was being done *synchronously*, which was blatently untrue! This was causing `end` to be called for some requests prematurely. I've now made changes to use callbacks, and deal with the fact that asynchronous request processing is happening in many cases.

        processRequest(params)
    }
    
    // MARK: AccountDelegate
    
    func saveToDatabase(account creds:Account) -> Bool {
        let result = self.repositories.user.updateCreds(creds: creds, forUser: creds.accountCreationUser!)
        Log.debug("saveToDatabase: result: \(result)")
        return result
    }
    
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
