//
//  UtilController.swift
//  Server
//
//  Created by Christopher Prince on 11/26/16.
//
//

import PerfectLib
import Credentials

class UtilController : ControllerProtocol {
    class func setup() -> Bool {
        return true
    }
    
    init() {
    }
    
    func healthCheck(request: RequestMessage, creds: Creds?, profile: UserProfile?,
        completion: @escaping (ResponseMessage?)->()) {
        let response = HealthCheckResponse()
        completion(response)
    }
    
    func checkPrimaryCreds(request: RequestMessage, creds: Creds?, profile: UserProfile?,
        completion: @escaping (ResponseMessage?)->()) {
        let response = CheckPrimaryCredsResponse()
        completion(response)
    }
}
