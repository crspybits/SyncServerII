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

public class ServerSetup {        
    // Just a guess. Don't know what's suitable for length. See https://github.com/IBM-Swift/Kitura/issues/917
    private static let secretStringLength = 256
    
    private static func randomString(length: Int) -> String {

        let letters : NSString = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
        let len = UInt32(letters.length)

        var randomString = ""

        for _ in 0 ..< length {
            let rand = arc4random_uniform(len)
            var nextChar = letters.character(at: Int(rand))
            randomString += NSString(characters: &nextChar, length: 1) as String
        }

        return randomString
    }

    static func credentials(_ router:Router) {
        let secret = self.randomString(length: secretStringLength)
        router.all(middleware: KituraSession.Session(secret: secret))
        
        // If credentials are not authorized by this middleware (e.g., valid Google creds), then an "unauthorized" HTTP code is sent back, with an empty response body.
        let credentials = Credentials()
        let googleCredentials = CredentialsGoogleToken()
        credentials.register(plugin: googleCredentials)
        
        router.all { (request, response, next) in
            Log.info(message: "REQUEST RECEIVED: \(request.urlURL.path)")
            
            for route in ServerEndpoints.session.all {
                if route.authenticationLevel == .none &&
                    route.path == request.urlURL.path {                    
                    next()
                    return
                }
            }
            
            credentials.handle(request: request, response: response, next: next)
        }
    }
}

public typealias ProcessRequest = (RequestProcessingParameters)->()

private class RequestHandler : CredsDelegate {
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
    }

    public func failWithError(message:String,
        statusCode:HTTPStatusCode = .internalServerError) {
        
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
    
    @discardableResult
    private func endWith(clientResponse:EndWithResponse) -> Bool {
        var jsonString:String?
        
        switch clientResponse {
        case .json(let jsonDict):
            do {
                jsonString = try jsonDict.jsonEncodedString()
            } catch (let error) {
                Log.error(message: "Failed on json encode: \(error.localizedDescription)")
                return false
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

        do {
            try self.response.end()
            Log.info(message: "Request completed with HTTP status code: \(response.statusCode)")
        } catch (let error) {
            Log.error(message: "Failed on `end` in failWithError: \(error.localizedDescription); HTTP status code: \(response.statusCode)")
            return false
        }
        
        Log.info(message: "REQUEST COMPLETED: \(request.urlURL.path)")
        
        return true
    }
    
    func setJsonResponseHeaders() {
        self.response.headers["Content-Type"] = "application/json"
    }
    
    // Starts a transaction, and calls the closure. If the closure returns true, then commits the transaction. Otherwise, rolls it back.
    private func dbTransaction(_ db:Database, dbOperations:()->(Bool)) {
        if !db.startTransaction() {
            self.failWithError(message: "Could not start a transaction!")
            return
        }
        
        let result = checkDeviceUUID()
        if result != nil && !result! {
            _ = db.rollback()
            return
        }
        
        if dbOperations() {
            if !db.commit() {
                Log.error(message: "Erorr during COMMIT operation!")
            }
        }
        else {
            if !db.rollback() {
                Log.error(message: "Erorr during ROLLBACK operation!")
            }
        }
    }
    
    func doRequest(createRequest: @escaping (RouterRequest) -> RequestMessage?,
        processRequest: @escaping ProcessRequest) {
        
        setJsonResponseHeaders()
        let profile = request.userProfile
        self.deviceUUID = request.headers[ServerConstants.httpRequestDeviceUUID]
        Log.info(message: "self.deviceUUID: \(self.deviceUUID)")
        
#if DEBUG
        if profile != nil {
            let userId = profile!.id
            let userName = profile!.displayName
            Log.info(message: "Profile: \(profile); userId: \(userId); userName: \(userName)")
        }
#endif

        let db = Database()
        repositories = Repositories(user: UserRepository(db), lock: LockRepository(db), masterVersion: MasterVersionRepository(db), fileIndex: FileIndexRepository(db), upload: UploadRepository(db), deviceUUID: DeviceUUIDRepository(db))
        
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
                    self.failWithError(message: "Could not convert Creds of type: \(currentSignedInUser!.accountType) from JSON: \(currentSignedInUser!.creds); error: \(errorString)")
                    return
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
        
        if profile == nil {
            assert(authenticationLevel! == .none)
            
            dbTransaction(db) {
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
            
            guard let profileCreds = Creds.toCreds(fromProfile: profile!, user:credsUser, delegate:self) else {
                failWithError(message: "Failed converting to Creds from profile", statusCode: .unauthorized)
                return
            }
                        
            dbTransaction(db) {
                return doRemainingRequestProcessing(dbCreds:dbCreds, profileCreds:profileCreds, requestObject: requestObject, db: db, profile: profile, processRequest: processRequest)
            }
        }
    }
    
    private func doRemainingRequestProcessing(dbCreds:Creds?, profileCreds:Creds?, requestObject:RequestMessage?, db: Database, profile: UserProfile?, processRequest: @escaping ProcessRequest) -> Bool {
        var success = true
                
        let params = RequestProcessingParameters(request: requestObject!, creds: dbCreds, profileCreds: profileCreds, userProfile: profile, currentSignedInUser: currentSignedInUser, db:db, repos:repositories, routerResponse:response, deviceUUID: self.deviceUUID) { responseObject in
        
            if nil == responseObject {
                self.failWithError(message: "Could not create response object from request object")
                success = false
                return
            }
            
            let jsonDict = responseObject!.toJSON()
            if nil == jsonDict {
                self.failWithError(message: "Could not convert response object to json dictionary")
                success = false
                return
            }
            
            switch responseObject!.responseType {
            case .json:
                self.endWith(clientResponse: .json(jsonDict!))

            case .data(let data):
                var jsonString:String?
                
                do {
                    jsonString = try jsonDict!.jsonEncodedString()
                } catch (let error) {
                    success = false
                    self.failWithError(message: "Could not convert json dict to string: \(error)")
                    return
                }
                
                self.endWith(clientResponse:
                    .data(data:data, headers:[ServerConstants.httpResponseMessageParams:jsonString!]))
            }
        }
        
        if self.endpoint.needsLock {
            let lock = Lock(userId:params.currentSignedInUser!.userId, deviceUUID:params.deviceUUID!)
            switch params.repos.lock.lock(lock: lock) {
            case .success:
                break
            
            // 2/11/16. We should never get here. With the transaction support just added, when server thread/request X attempts to obtain a lock and (a) another server thread/request (Y) has previously started a transaction, and (b) has obtained a lock in this manner, but (c) not ended the transaction, (d) a *transaction-level* lock will be obtained on the lock table row by request Y. Request X will be *blocked* in the server until the request Y completes its transaction.
            case .lockAlreadyHeld:
                self.failWithError(message: "Could not obtain lock!!")
                success = false
            
            case .errorRemovingStaleLocks, .modelValueWasNil, .otherError:
                self.failWithError(message: "Error obtaining lock!")
                success = false
            }
        }
        
        if success {
            processRequest(params)
        }
        
        if success && self.endpoint.needsLock {
            _ = params.repos.lock.unlock(userId: params.currentSignedInUser!.userId)
        }
        
        return success
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
                        failWithError(message: "Exceeded maximum UUIDs per user: \(repositories.deviceUUID.maximumNumberOfDeviceUUIDsPerUser)")
                        return false
                        
                    case .success:
                        return true
                    }
                }
            }
        }
    }
}

class CreateRoutes {
    private var router = Router()

    init() {
    }
    
    func addRoute(ep:ServerEndpoint,
        createRequest: @escaping (RouterRequest) ->(RequestMessage?),
        processRequest: @escaping ProcessRequest) {
        
        func handleRequest(routerRequest:RouterRequest, routerResponse:RouterResponse) {
            Log.info(message: "parsedURL: \(routerRequest.parsedURL)")
            let handler = RequestHandler(request: routerRequest, response: routerResponse, endpoint:ep)
            handler.doRequest(createRequest: createRequest, processRequest: processRequest)
        }
        
        switch (ep.method) {
        case .get:
            self.router.get(ep.path) { routerRequest, routerResponse, _ in
                handleRequest(routerRequest: routerRequest, routerResponse: routerResponse)
            }
            
        case .post:
            self.router.post(ep.path) { routerRequest, routerResponse, _ in
                handleRequest(routerRequest: routerRequest, routerResponse: routerResponse)
            }
        
        case .delete:
            self.router.delete(ep.path) { routerRequest, routerResponse, _ in
                handleRequest(routerRequest: routerRequest, routerResponse: routerResponse)
            }
        }
    }
    
    func getRoutes() -> Router {
        ServerSetup.credentials(self.router)
        ServerRoutes.add(proxyRouter: self)

        self.router.error { request, response, _ in
            let handler = RequestHandler(request: request, response: response)
            
            let errorDescription: String
            if let error = response.error {
                errorDescription = "\(error)"
            } else {
                errorDescription = "Unknown error"
            }
            
            let message = "Server error: \(errorDescription)"
            handler.failWithError(message: message)
        }

        self.router.all { request, response, _ in
            let handler = RequestHandler(request: request, response: response)
            let message = "Route not found in server: \(request.originalURL)"
            response.statusCode = .notFound
            handler.failWithError(message: message)
        }
        
        return self.router
    }
}
