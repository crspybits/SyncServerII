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
    
    func healthCheck(_ request: RequestMessage, creds:Creds?, profile:UserProfile?) -> HealthCheckResponse? {
        let response = HealthCheckResponse()
        return response
    }
    
    func checkPrimaryCreds(_ request: RequestMessage, creds:Creds?, profile:UserProfile?) -> CheckPrimaryCredsResponse? {
        let response = CheckPrimaryCredsResponse()
        return response
    }
}
