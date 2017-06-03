//
//  ServerSetup.swift
//  Server
//
//  Created by Christopher Prince on 12/4/16.
//
//

import PerfectLib
import Kitura
import KituraNet
import Gloss
import KituraSession
import Credentials
import CredentialsGoogle
import Foundation

/* I'm getting the following error, after having started using SSL and self-signing certificates:
[2017-05-20T21:26:32.218-06:00] [ERROR] [IncomingSocketHandler.swift:148 handleRead()] Read from socket (file descriptor 15) failed. Error = Error code: -9806(0x-264E), ERROR: SSLRead, code: -9806, reason: errSSLClosedAbort.
See also: https://github.com/IBM-Swift/Kitura-net/issues/196
*/

public typealias ProcessRequest = (RequestProcessingParameters)->()

class RequestHandler : CredsDelegate {
    private var request:RouterRequest!
    private var response:RouterResponse!
    
    private var repositories:Repositories!
    private var authenticationLevel:AuthenticationLevel!
    private var currentSignedInUser:User?
    private var deviceUUID:String?
    private var endpoint:ServerEndpoint!
    private static var numberCreated = 0
    private static var numberDeleted = 0
    
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
        
        RequestHandler.numberCreated += 1
        Log.info(message: "RequestHandler.init: numberCreated: \(RequestHandler.numberCreated); numberDeleted: \(RequestHandler.numberDeleted);")
    }
    
    deinit {
        RequestHandler.numberDeleted += 1
        Log.info(message: "RequestHandler.deinit: numberCreated: \(RequestHandler.numberCreated); numberDeleted: \(RequestHandler.numberDeleted);")
    }

    public func failWithError(message:String, statusCode:HTTPStatusCode = .internalServerError) {
        
        setJsonResponseHeaders()
        Log.error(message: message)

        self.response.statusCode = statusCode
        
        let result = [
            "error" : message
        ]
        self.endWith(clientResponse: .json(result))
    }
    
    enum EndWithResponse {
    case json(JSON)
    case data(data:Data?, headers:[String:String])
    }
    
    private func endWith(clientResponse:EndWithResponse) {
        var jsonString:String?
        
        switch clientResponse {
        case .json(let jsonDict):
            
            do {
                jsonString = try jsonDict.jsonEncodedString()
            } catch (let error) {
                let message = "Failed on json encode: \(error.localizedDescription) for jsonDict: \(jsonDict)"
                Log.error(message: message)
                self.response.statusCode = HTTPStatusCode.internalServerError
                self.response.send(message)
            }
            
            if jsonString != nil {
                self.response.send(jsonString!)
            }
            
        case .data(data: let data, headers: let headers):
            for (key, value) in headers {
                self.response.headers.append(key, value: value)
            }
            
            if data != nil {
                self.response.send(data: data!)
            }
        }
        
        Log.info(message: "REQUEST \(request.urlURL.path): ABOUT TO END ...")

        do {
            try self.response.end()
            Log.info(message: "REQUEST \(request.urlURL.path): STATUS CODE: \(response.statusCode)")
        } catch (let error) {
            Log.error(message: "Failed on `end` in failWithError: \(error.localizedDescription); HTTP status code: \(response.statusCode)")
        }
        
        Log.info(message: "REQUEST \(request.urlURL.path): COMPLETED")
    }
    
    func setJsonResponseHeaders() {
        self.response.headers["Content-Type"] = "application/json"
    }
    
    enum SuccessResult {
        case json(JSON)
        case dataWithHeaders(Data?, headers:[String:String])
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
    
    // Starts a transaction, and calls the closure. If the closure succeeds (no error), then commits the transaction. Otherwise, rolls it back.
    private func dbTransaction(_ db:Database, dbOperations:()->(ServerResult)) -> ServerResult {
    
        if !db.startTransaction() {
            return .failure(.message("Could not start a transaction!"))
        }
        
        let result = checkDeviceUUID()
        if result != nil && !result! {
            _ = db.rollback()
            return .failure(.message("No Device UUID with header!"))
        }
        
        var operationResult = dbOperations()
        
        switch operationResult {
        case .success(_):
            if !db.commit() {
                let message = "Error during COMMIT operation!"
                operationResult = .failure(.message(message))
                Log.error(message: message)
            }
            
        case .failure(_):
            if !db.rollback() {
                let message = "Error during ROLLBACK operation!"
                operationResult = .failure(.message(message))
                Log.error(message: message)
            }
        }
        
        return operationResult
    }
    
    func doRequest(createRequest: @escaping (RouterRequest) -> RequestMessage?,
        processRequest: @escaping ProcessRequest) {
        
        setJsonResponseHeaders()
        let profile = request.userProfile
        self.deviceUUID = request.headers[ServerConstants.httpRequestDeviceUUID]
        Log.info(message: "self.deviceUUID: \(String(describing: self.deviceUUID))")
        
#if DEBUG
        if profile != nil {
            let userId = profile!.id
            let userName = profile!.displayName
            Log.info(message: "Profile: \(String(describing: profile)); userId: \(userId); userName: \(userName)")
        }
#endif

        let db = Database()
        repositories = Repositories(user: UserRepository(db), lock: LockRepository(db), masterVersion: MasterVersionRepository(db), fileIndex: FileIndexRepository(db), upload: UploadRepository(db), deviceUUID: DeviceUUIDRepository(db), sharing: SharingInvitationRepository(db))
        
        switch authenticationLevel! {
        case .none:
            break
            
        case .primary, .secondary:
            if profile == nil {
                // We should really never get here. Credentials security check should make sure of that. This is a double check.
                let message = "YIKES: Should have had a user profile!"
                Log.critical(message: message)
                failWithError(message: message)
                return
            }
        }
        
        var dbCreds:Creds?

        if authenticationLevel! == .secondary {
            // We have .secondary authentication-- i.e., we should have the user recorded in the database already.

            guard let accountType = AccountType.fromSpecificCredsType(specificCreds: profile!.accountSpecificCreds!) else {
                self.failWithError(message: "Could not convert fromSpecificCredsType.")
                return
            }
            
            let key = UserRepository.LookupKey.accountTypeInfo(accountType:accountType, credsId: profile!.id)
            let userLookup = self.repositories.user.lookup(key: key, modelInit: User.init)
        
            switch userLookup {
            case .found(let model):
                currentSignedInUser = (model as? User)!
                var errorString:String?
                
                do {
                    dbCreds = try Creds.toCreds(accountType: currentSignedInUser!.accountType, fromJSON: currentSignedInUser!.creds, user: .user(currentSignedInUser!), delegate:self)
                } catch (let error) {
                    errorString = "\(error)"
                }
                
                if errorString != nil || dbCreds == nil {
                    self.failWithError(message: "Could not convert Creds of type: \(currentSignedInUser!.accountType) from JSON: \(currentSignedInUser!.creds); error: \(String(describing: errorString))")
                    return
                }
                
                // This user is on the system. If they are a sharing user, make sure they have the minimum permission to execute this endpoint.
                if currentSignedInUser!.userType == .sharing {
                    guard currentSignedInUser!.sharingPermission!.hasMinimumPermission(endpoint.minSharingPermission) else {
                        self.failWithError(message: "Signed in user has sharing permissions of \(currentSignedInUser!.sharingPermission!) but these don't meet the minimum requirements of \(endpoint.minSharingPermission)", statusCode: .unauthorized)
                        return
                    }
                }
                
            case .noObjectFound:
                failWithError(message: "Failed on secondary authentication", statusCode: .unauthorized)
                return
                
            case .error(let error):
                self.failWithError(message: "Failed looking up user: \(key): \(error)", statusCode: .internalServerError)
                return
            }
        }
        
        let requestObject:RequestMessage? = createRequest(request)
        if nil == requestObject {
            self.failWithError(message: "Could not create request object from RouterRequest: \(request)")
            return
        }
        
#if DEBUG
        // Failure testing.
        if request.headers[ServerConstants.httpRequestEndpointFailureTestKey] != nil {
            self.failWithError(message: "Failure test requested by client.")
            return
        }
#endif
        
        // 6/1/17; Up until this point, I had been (a) calling .end on the RouterResponse object, and (b) only after that committing the transaction (or rolling it back) on the database. However, that can generate some unwanted asynchronous processing. i.e., the network caller can potentially initiate another request *before* the database commit completes. Instead, I should be: (a) committing (or rolling back) the transaction, and then (b) calling .end. That should provide the synchronous character that I really want.
        
        var transactionResult:ServerResult!
        
        if profile == nil {
            assert(authenticationLevel! == .none)
            
            transactionResult = dbTransaction(db) {
                return doRemainingRequestProcessing(dbCreds: nil, profileCreds:nil, requestObject: requestObject, db: db, profile: nil, processRequest: processRequest)
            }
        }
        else {
            var credsUser:CredsUser?
            switch authenticationLevel! {
            case .primary:
                // We don't have a userId yet for this user.
                break
                
            case .secondary:
                credsUser = .user(self.currentSignedInUser!)
                
            case .none:
                assertionFailure("Should never get here with authenticationLevel == .none!")
            }
            
            if let profileCreds = Creds.toCreds(fromProfile: profile!, user:credsUser, delegate:self) {
                transactionResult = dbTransaction(db) {
                    return doRemainingRequestProcessing(dbCreds:dbCreds, profileCreds:profileCreds, requestObject: requestObject, db: db, profile: profile, processRequest: processRequest)
                }
            }
            else {
                transactionResult = .failure(.messageWithStatus("Failed converting to Creds from profile", .unauthorized))
            }
        }
        
        // `endWith` and `failWithError` call the `RouterResponse` `end` method, and thus we have waited until the very end of processing of the request to finish and return control back to the caller.
        switch transactionResult! {
        case .success(.json(let json)):
            endWith(clientResponse: .json(json))
        
        case .success(.dataWithHeaders(let data, headers: let headers)):
            endWith(clientResponse: .data(data: data, headers: headers))
        
        case .success(.nothing):
            endWith(clientResponse: .json([:]))
            
        case .failure(.message(let message)):
            failWithError(message: message)
        
        case .failure(.messageWithStatus(let message, let statusCode)):
            failWithError(message: message, statusCode: statusCode)
        }
    }
    
    private func doRemainingRequestProcessing(dbCreds:Creds?, profileCreds:Creds?, requestObject:RequestMessage?, db: Database, profile: UserProfile?, processRequest: @escaping ProcessRequest) -> ServerResult {
    
        var effectiveOwningUserCreds:Creds?
        
        if currentSignedInUser != nil {
            let effectiveOwningUserKey = UserRepository.LookupKey.userId(currentSignedInUser!.effectiveOwningUserId)
            let userResults = UserRepository(db).lookup(key: effectiveOwningUserKey, modelInit: User.init)
            guard case .found(let model) = userResults,
                let effectiveOwningUser = model as? User else {
                return .failure(.message("Could not get effective owning user from database."))
            }
            
            effectiveOwningUserCreds = effectiveOwningUser.credsObject
            guard effectiveOwningUserCreds != nil else {
                return .failure(.message("Could not get effective owning user creds."))
            }
        }

        var operationResult:ServerResult = .success(.nothing)

        let params = RequestProcessingParameters(request: requestObject!, ep:self.self.endpoint, creds: dbCreds, effectiveOwningUserCreds: effectiveOwningUserCreds, profileCreds: profileCreds, userProfile: profile, currentSignedInUser: currentSignedInUser, db:db, repos:repositories, routerResponse:response, deviceUUID: self.deviceUUID) { responseObject in
        
            if nil == responseObject {
                operationResult = .failure(.message("Could not create response object from request object"))
                return
            }
            
            let jsonDict = responseObject!.toJSON()
            if nil == jsonDict {
                operationResult = .failure(.message("Could not convert response object to json dictionary"))
                return
            }
            
            switch responseObject!.responseType {
            case .json:
                operationResult = .success(.json(jsonDict!))

            case .data(let data):
                var jsonString:String?
                
                do {
                    jsonString = try jsonDict!.jsonEncodedString()
                } catch (let error) {
                    operationResult = .failure(.message("Could not convert json dict to string: \(error)"))
                    return
                }
                
                operationResult = .success(.dataWithHeaders(data, headers:[ServerConstants.httpResponseMessageParams:jsonString!]))
            }
        }
        
        if self.endpoint.needsLock {
            let lock = Lock(userId:params.currentSignedInUser!.effectiveOwningUserId, deviceUUID:params.deviceUUID!)
            switch params.repos.lock.lock(lock: lock) {
            case .success:
                break
            
            // 2/11/16. We should never get here. With the transaction support just added, when server thread/request X attempts to obtain a lock and (a) another server thread/request (Y) has previously started a transaction, and (b) has obtained a lock in this manner, but (c) not ended the transaction, (d) a *transaction-level* lock will be obtained on the lock table row by request Y. Request X will be *blocked* in the server until the request Y completes its transaction.
            case .lockAlreadyHeld:
                return .failure(.message("Could not obtain lock!!"))
            
            case .errorRemovingStaleLocks, .modelValueWasNil, .otherError:
                return .failure(.message("Error obtaining lock!"))
            }
        }
        
        processRequest(params)
        
        if self.endpoint.needsLock {
            _ = params.repos.lock.unlock(userId: params.currentSignedInUser!.effectiveOwningUserId)
        }
        
        return operationResult
    }
    
    // MARK: CredsDelegate
    
    func saveToDatabase(creds:Creds, user:CredsUser) -> Bool {
        let result = self.repositories.user.updateCreds(creds: creds, forUser: user)
        Log.debug(message: "saveToDatabase: result: \(result)")
        return result
    }
    
    // MARK:
    
    // Returns true success, nil if a UUID is not needed, and false if failure.
    private func checkDeviceUUID() -> Bool? {
        switch authenticationLevel! {
        case .none:
            return nil
            
        case .primary, .secondary:
            if self.deviceUUID == nil {
                self.failWithError(message: "Did not provide a Device UUID with header \(ServerConstants.httpRequestDeviceUUID)")
                return false
            }
            else if currentSignedInUser == nil && authenticationLevel == .primary {
                // If we don't have a signed in user, we can't search for existing deviceUUID's. But that's not an error.
                return true
            }
            else {
                let key = DeviceUUIDRepository.LookupKey.deviceUUID(self.deviceUUID!)
                let result = repositories.deviceUUID.lookup(key: key, modelInit: DeviceUUID.init)
                switch result {
                case .error(let error):
                    failWithError(message: "Error looking up device UUID: \(error)")
                    return false
                    
                case .found(_):
                    return true
                    
                case .noObjectFound:
                    let newDeviceUUID = DeviceUUID(userId: currentSignedInUser!.userId, deviceUUID: self.deviceUUID!)
                    let addResult = repositories.deviceUUID.add(deviceUUID: newDeviceUUID)
                    switch addResult {
                    case .error(let error):
                        failWithError(message: "Error adding new device UUID: \(error)")
                        return false
                        
                    case .exceededMaximumUUIDsPerUser:
                        failWithError(message: "Exceeded maximum UUIDs per user: \(String(describing: repositories.deviceUUID.maximumNumberOfDeviceUUIDsPerUser))")
                        return false
                        
                    case .success:
                        return true
                    }
                }
            }
        }
    }
}
