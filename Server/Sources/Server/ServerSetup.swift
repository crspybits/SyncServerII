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

public class CreateRoutes {
    private var router = Router()
    private var request:RouterRequest!
    private var response:RouterResponse!

    init() {
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
    
    // The intent is that, if authorized, a request never returns an empty response. Some JSON is always returned, even with an error.
    private func doRequest(authenticationLevel:AuthenticationLevel = .secondary, createRequest: @escaping (JSON) -> RequestMessage?,
        processRequest:@escaping (RequestMessage, Creds?, UserProfile?)->(ResponseMessage?)) {
        
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
        
        var secondaryAuthUser:User?
        
        if authenticationLevel == .secondary {
            let userExists = UserController.userExists(userProfile: profile!)
            switch userExists {
            case .error:
                failWithError(message: "Failed on secondary authentication", statusCode: .internalServerError)
                return
                
            case .doesNotExist:
                failWithError(message: "Failed on secondary authentication", statusCode: .unauthorized)
                return
                
            case .exists(let user):
                secondaryAuthUser = user
            }
        }
        
        let params = self.request.queryParameters
        let requestObject:RequestMessage? = createRequest(params)
        if nil == requestObject {
            self.failWithError(message: "Could not create request object from parameters: \(params)")
            return
        }
        
        func doTheRequestProcessing(creds:Creds?) -> Bool {
            let responseObject = processRequest(requestObject!, creds, profile)
            if nil == responseObject {
                self.failWithError(message: "Could not create response object from request object")
                return false
            }
            
            let jsonDict = responseObject!.toJSON()
            if nil == jsonDict {
                self.failWithError(message: "Could not convert response object to json dictionary")
                return false
            }
            
            return self.endWith(jsonDict: jsonDict)
        }

        // TODO: Starts a transaction, and calls the closure. If the closure returns true, then commits the transaction. Otherwise, rolls it back.
        func dbTransaction(dbOperations:()->(Bool)) {
            dbOperations()
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
            
            creds.generateTokens() { success, error in
                if error == nil {
                    dbTransaction() {
                        if success! && authenticationLevel == .secondary {
                            // Only update the creds on a secondary auth level, because only then do we know that we know about the user already.
                            if !UserRepository.updateCreds(creds: creds, forUser: secondaryAuthUser!) {
                                self.failWithError(message: "Could not update creds")
                                return false
                            }
                        }
                        
                        return doTheRequestProcessing(creds: creds)
                    }
                }
                else {
                    self.failWithError(message: "Failed attempting to generate tokens")
                }
            }
        }
    }
    
    public func addRoute(ep:ServerEndpoint,
        createRequest: @escaping (_ json: JSON) ->(RequestMessage?),
        processRequest: @escaping (RequestMessage, Creds?, UserProfile?)->(ResponseMessage?)) {
        
        func handleRequest(routerRequest:RouterRequest, routerResponse:RouterResponse) {
            self.response = routerResponse; self.request = routerRequest
            
            self.doRequest(authenticationLevel: ep.authenticationLevel,
                createRequest: createRequest) { request, creds, profile in
                return processRequest(request, creds, profile)
            }
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
            self.request = request; self.response = response
            
            let errorDescription: String
            if let error = response.error {
                errorDescription = "\(error)"
            } else {
                errorDescription = "Unknown error"
            }
            
            let message = "Server error: \(errorDescription)"
            self.failWithError(message: message)
        }

        self.router.all { request, response, _ in
            self.request = request; self.response = response
            let message = "Route not found in server: \(request.originalURL)"
            response.statusCode = .notFound
            self.failWithError(message: message)
        }
        
        return self.router
    }
}
