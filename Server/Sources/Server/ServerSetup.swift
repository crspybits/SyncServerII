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

private class RequestHandler {
    private var request:RouterRequest!
    private var response:RouterResponse!
    
    init(request:RouterRequest, response:RouterResponse) {
        self.request = request
        self.response = response
    }

    public func failWithError(message:String,
        statusCode:HTTPStatusCode = .internalServerError) {
        
        setJsonResponseHeaders()
        Log.error(message: message)

        self.response.statusCode = statusCode
        
        let result = [
            "error" : message
        ]
        _ = self.endWith(jsonDict: result)
    }
    
    private func endWith(jsonDict:JSON?) -> Bool {
        var jsonString:String?
        
        do {
            jsonString = try jsonDict.jsonEncodedString()
        } catch (let error) {
            Log.error(message: "Failed on json encode: \(error.localizedDescription)")
            return false
        }
        
        if jsonString != nil {
            self.response.send(jsonString!)
        }

        do {
            try self.response.end()
            Log.info(message: "Request completed with HTTP status code: \(response.statusCode)")
        } catch (let error) {
            Log.error(message: "Failed on `end` in failWithError: \(error.localizedDescription); HTTP status code: \(response.statusCode)")
            return false
        }
        
        return true
    }
    
    func setJsonResponseHeaders() {
        self.response.headers["Content-Type"] = "application/json"
    }

    func doRequest(authenticationLevel:AuthenticationLevel = .secondary,
        createRequest: @escaping (RouterRequest) -> RequestMessage?,
        processRequest: @escaping ProcessRequest) {
        
        Log.info(message: "Processing Request: \(request.urlURL.path)")
        setJsonResponseHeaders()
        
        let profile = request.userProfile

#if DEBUG
        if profile != nil {
            let userId = profile!.id
            let userName = profile!.displayName
            Log.info(message: "Profile: \(profile); userId: \(userId); userName: \(userName)")
        }
#endif

        switch authenticationLevel {
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
        
        var currentSignedInUser:User?
        
        let db = Database()
        let repositories = Repositories(user: UserRepository(db), lock: LockRepository(db), masterVersion: MasterVersionRepository(db), fileIndex: FileIndexRepository(db), upload: UploadRepository(db))
        
        if authenticationLevel == .secondary {
            let userExists = UserController.userExists(userProfile: profile!, userRepository: repositories.user)
            switch userExists {
            case .error:
                failWithError(message: "Failed on secondary authentication", statusCode: .internalServerError)
                return
                
            case .doesNotExist:
                failWithError(message: "Failed on secondary authentication", statusCode: .unauthorized)
                return
                
            case .exists(let user):
                currentSignedInUser = user
            }
        }
        
        let requestObject:RequestMessage? = createRequest(request)
        if nil == requestObject {
            self.failWithError(message: "Could not create request object from RouterRequest: \(request)")
            return
        }
        
        func doTheRequestProcessing(creds:Creds?) -> Bool {
            var success = true
            
            let params = RequestProcessingParameters(request: requestObject!, creds: creds, userProfile: profile, currentSignedInUser: currentSignedInUser, db:db, repos:repositories) { responseObject in
            
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
                
                _ = self.endWith(jsonDict: jsonDict)
            }
            
            processRequest(params)
            return success
        }

        // Starts a transaction, and calls the closure. If the closure returns true, then commits the transaction. Otherwise, rolls it back.
        func dbTransaction(dbOperations:()->(Bool)) {
            if !db.startTransaction() {
                self.failWithError(message: "Could not start a transaction!")
                return
            }
            
            if dbOperations() {
                // Already finished the operation. Can't report an error if it happens here.
                _ = db.commit()
            }
            else {
                // We already had an error. What's the point in checking for an error on the rollback?
                _ = db.rollback()
            }
        }
        
        if profile == nil {
            dbTransaction() {
                return doTheRequestProcessing(creds: nil)
            }
        }
        else {
            guard let creds = Creds.toCreds(fromProfile: profile!) else {
                failWithError(message: "Failed converting to Creds from profile", statusCode: .unauthorized)
                return
            }
            
            // It is not an error at this point to *not* have a server auth code. With most endpoints we won't have it.
            
            creds.generateTokens() { successGeneratingTokens, error in
                if error == nil {
                    dbTransaction() {
                        if successGeneratingTokens! && authenticationLevel == .secondary {
                            // Only update the creds on a secondary auth level, because only then do we know that we know about the user already.
                            if !repositories.user.updateCreds(creds: creds, forUser: currentSignedInUser!) {
                                self.failWithError(message: "Could not update creds")
                            }
                        }
                        
                        let result = doTheRequestProcessing(creds: creds)
                        Log.debug(message: "doTheRequestProcessing: \(result)")
                        return result
                    }
                }
                else {
                    self.failWithError(message: "Failed attempting to generate tokens")
                }
            }
        }
    }
}

public class CreateRoutes {
    private var router = Router()

    init() {
    }
    
    public func addRoute(ep:ServerEndpoint,
        createRequest: @escaping (RouterRequest) ->(RequestMessage?),
        processRequest: @escaping ProcessRequest) {
        
        func handleRequest(routerRequest:RouterRequest, routerResponse:RouterResponse) {
            Log.info(message: "parsedURL: \(routerRequest.parsedURL)")
            
            let handler = RequestHandler(request: routerRequest, response: routerResponse)
            handler.doRequest(authenticationLevel: ep.authenticationLevel,
                createRequest: createRequest, processRequest: processRequest)
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
