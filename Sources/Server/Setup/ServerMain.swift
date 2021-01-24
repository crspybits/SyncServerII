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
import Kitura
import ServerShared

// If given, the single command line argument to the server is expected to be a full path to the server config file.

public class ServerMain {
    // If server fails to start, try looking for a process using the server's port:
    //      sudo lsof -i -n -P | grep TCP | grep 8080
        
    public enum ServerStartup {
        case blocking // doesn't return from startup (normal case)
        case nonBlocking // returns from startup (for XCTests)
    }
    
    public class func startup(type:ServerStartup = .blocking) {
        // Set the logging level
        HeliumLogger.use(.debug)
        
        Log.info("Launching server in \(type) mode with \(CommandLine.arguments.count) command line arguments.")
        
        if type == .blocking {
            do {
                // When we launch the server from within Xcode (or just with no explicit arguments), we have 1 "argument" (CommandLine.arguments[0]).
                if CommandLine.arguments.count == 1 {
                    try Configuration.setup(configFileFullPath: ServerConfiguration.serverConfigFile)
                }
                else {
                    let configFile = CommandLine.arguments[1]
                    Log.info("Loading server config file from: \(configFile)")
                    try Configuration.setup(configFileFullPath: configFile)
                }
            } catch (let error) {
                Startup.halt("Failed during startup: Could not load config file: \(error)")
                return
            }
        }
        
        if !Controllers.setup() {
            Startup.halt("Failed during startup: Could not setup controller(s).")
            return
        }
        
        guard let db = Database(showStartupInfo: true) else {
            Startup.halt("Failed during startup: Could not connect to database.")
            return
        }
        
        if !Database.setup(db: db) {
            Startup.halt("Failed during startup: Could not setup database tables(s).")
            return
        }
        db.close()

        let accountManager = AccountManager()
        let resolverManager = ChangeResolverManager()
        
        do {
            try resolverManager.setupResolvers()
        } catch let error {
            Startup.halt("Failed during startup: Failed setting up Resolvers: \(error)")
            return
        }
        
        guard let services = Services(accountManager: accountManager, changeResolverManager: resolverManager) else {
            Startup.halt("Failed during startup: Failed setting up Services")
            return
        }
        
        Log.info("Using mime types: \(MimeType.allCases)")
       
        let routes = CreateRoutes.getRoutes(services: services)
        
        Kitura.addHTTPServer(onPort: Configuration.server.port, with: routes)
        
        switch type {
        case .blocking:
            Kitura.run()
            
        case .nonBlocking:
            Kitura.start()
        }
    }
    
    // For testing
    public class func shutdown() {
        Kitura.stop()
    }
}
