//
//  CreateRoutes.swift
//  Server
//
//  Created by Christopher Prince on 6/2/17.
//
//

import Foundation
import Kitura
import ServerShared
import LoggerAPI

class CreateRoutes {
    private init() {}
    
    private static func addRoute(ep:ServerEndpoint, processRequest: @escaping ProcessRequest, services: Services, router: Router) {
        func handleRequest(routerRequest:RouterRequest, routerResponse:RouterResponse) {
            Log.info("parsedURL: \(routerRequest.parsedURL)")
            let handler = RequestHandler(request: routerRequest, response: routerResponse, services: services, endpoint:ep)
            
            func create(routerRequest: RouterRequest) -> RequestMessage? {
                let queryDict = routerRequest.queryParameters
                Log.debug("queryDict: \(queryDict)")
                guard let request = try? ep.requestMessageType.decode(queryDict) else {
                    Log.error("Error doing request decode")
                    return nil
                }
                
                do {
                    try request.setup(routerRequest: routerRequest)
                } catch (let error) {
                    Log.error("Error doing request setup: \(error)")
                    return nil
                }
                
                guard request.valid() else {
                    Log.error("Error: Request is not valid.")
                    return nil
                }
                
                return request
            }
            
            handler.doRequest(createRequest: create, processRequest: processRequest)
        }
        
        switch (ep.method) {
        case .get:
            router.get(ep.pathWithSuffixSlash) { routerRequest, routerResponse, _ in
                handleRequest(routerRequest: routerRequest, routerResponse: routerResponse)
            }
            
        case .post:
            router.post(ep.pathWithSuffixSlash) { routerRequest, routerResponse, _ in
                handleRequest(routerRequest: routerRequest, routerResponse: routerResponse)
            }
        
        case .patch:
            router.patch(ep.pathWithSuffixSlash) { routerRequest, routerResponse, _ in
                handleRequest(routerRequest: routerRequest, routerResponse: routerResponse)
            }
        
        case .delete:
            router.delete(ep.pathWithSuffixSlash) { routerRequest, routerResponse, _ in
                handleRequest(routerRequest: routerRequest, routerResponse: routerResponse)
            }
        }
    }
    
    static func getRoutes(services: Services) -> Router {
        let router = Router()
        
        let accountRoutes = ServerSetup.credentials(router, accountManager: services.accountManager)
        
        let routes = ServerRoutes.routes() + accountRoutes
        for (endpoint, controllerMethod) in routes {
            addRoute(ep: endpoint, processRequest: controllerMethod, services: services, router: router)
        }

        router.error { request, response, _ in
            let handler = RequestHandler(request: request, response: response, services: services)
            
            let errorDescription: String
            if let error = response.error {
                errorDescription = "\(error)"
            } else {
                errorDescription = "Unknown error"
            }
            
            let message = "Server error: \(errorDescription)"
            handler.failWithError(message: message)
        }

        router.all { request, response, _ in
            let handler = RequestHandler(request: request, response: response, services: services)
            let message = "Route not found in server: \(request.originalURL)"
            response.statusCode = .notFound
            handler.failWithError(message: message)
        }
        
        return router
    }
}

