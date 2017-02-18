//
//  ServerMain.swift
//  Server
//
//  Created by Christopher Prince on 12/3/16.
//
//

import Foundation
import HeliumLogger
import LoggerAPI
import PerfectLib
import Kitura

public class ServerMain {
    // If server fails to start, try looking for a process using the port:
    //      sudo lsof -i -n -P | grep TCP | grep 8181
    public static let port = 8181
    
    public enum ServerStartup {
        case blocking // doesn't return from startup (normal case)
        case nonBlocking // returns from startup (for XCTests)
    }
    
    public class func startup(type:ServerStartup = .blocking) {
        if type == .blocking {
            Constants.setup(configFileName: Constants.serverConfigFile)
        }
        
        Log.logger = HeliumLogger()
        
        if !Controllers.setup() {
            Log.error("Failed during startup: Could not setup controller(s).")
            exit(1)
        }

        let serverRoutes = CreateRoutes()
        Kitura.addHTTPServer(onPort: self.port, with: serverRoutes.getRoutes())
        
        switch type {
        case .blocking:
            Kitura.run()
            
        case .nonBlocking:
            Kitura.start()
        }
    }
    
    public class func shutdown() {
        Kitura.stop()
    }
}
