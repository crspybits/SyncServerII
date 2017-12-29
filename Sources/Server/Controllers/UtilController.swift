//
//  UtilController.swift
//  Server
//
//  Created by Christopher Prince on 11/26/16.
//
//

import LoggerAPI
import Credentials
import SyncServerShared
import Foundation

class UtilController : ControllerProtocol {
    static var serverStart:Date!
    
    class func setup(db:Database) -> Bool {
        serverStart = Date()
        return true
    }
    
    func healthCheck(params:RequestProcessingParameters) {
        let response = HealthCheckResponse()!
        
        response.currentServerDateTime = Date()
        response.serverUptime = -UtilController.serverStart.timeIntervalSinceNow
        response.deployedGitTag = Constants.session.deployedGitTag
        
        let stats = ServerStatsKeeper.session.stats
        var diagnostics = ""
        for (key, value) in stats {
            diagnostics += "\(key.rawValue): \(value); "
        }
        
        if diagnostics.count > 0 {
            response.diagnostics = diagnostics
        }
        
        params.completion(response)
    }
    
    func checkPrimaryCreds(params:RequestProcessingParameters) {
        let response = CheckPrimaryCredsResponse()
        params.completion(response)
    }
}
