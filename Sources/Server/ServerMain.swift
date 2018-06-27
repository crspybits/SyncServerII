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

// 7/2/17; SwiftMetrics, perhaps because it was mis-installed, was causing several of my higher-performing test cases to fail. E.g., 10 consecutive uploads and downloads of a 1MB file. Thus, I've commented it out for now.

// import SwiftMetrics
// import SwiftMetricsDash

// If given, the single command line argument to the server is expected to be a full path to the server config file.

public class ServerMain {
    // If server fails to start, try looking for a process using the server's port:
    //      sudo lsof -i -n -P | grep TCP | grep 8080
    
    // static var smd:SwiftMetricsDash?
    
    public enum ServerStartup {
        case blocking // doesn't return from startup (normal case)
        case nonBlocking // returns from startup (for XCTests)
    }
    
    public class func startup(type:ServerStartup = .blocking) {
        // Set the logging level
        HeliumLogger.use(.debug)
        
        Log.info("Launching server in \(type) mode with \(CommandLine.arguments.count) command line arguments.")
        
        // http://www.kitura.io/en/resources/tutorials/swiftmetrics.html
        // https://developer.ibm.com/swift/2017/03/21/using-swiftmetrics-secure-kitura-server/
        // Enable SwiftMetrics Monitoring
        //let sm = try! SwiftMetrics()
        // Pass SwiftMetrics to the dashboard for visualising
        //smd = try? SwiftMetricsDash(swiftMetricsInstance : sm)
        
        if type == .blocking {
            do {
                // When we launch the server from within Xcode (or just with no explicit arguments), we have 1 "argument" (CommandLine.arguments[0]).
                if CommandLine.arguments.count == 1 {
                    try Constants.setup(configFileName: Constants.serverConfigFile)
                }
                else {
                    let configFile = CommandLine.arguments[1]
                    Log.info("Loading server config file from: \(configFile)")
                    try Constants.setup(configFileFullPath: configFile)
                }
            } catch (let error) {
                Log.error("Failed during startup: Could not load config file: \(error)")
                exit(1)
            }
        }
        
        if !Controllers.setup() {
            Log.error("Failed during startup: Could not setup controller(s).")
            exit(1)
        }
        
        if !Database.setup() {
            Log.error("Failed during startup: Could not setup database tables(s).")
            exit(1)
        }

        let serverRoutes = CreateRoutes()

        if Constants.session.ssl.usingKituraSSL {
#if os(Linux)
            let sslConfig = SSLConfig(
                    withCACertificateDirectory: Constants.session.ssl.caCertificateDirectory,
                    usingCertificateFile: Constants.session.ssl.certFile,
                    withKeyFile: Constants.session.ssl.keyFile,
                    usingSelfSignedCerts: Constants.session.ssl.selfSigning)
#else // on macOS
            let sslConfig = SSLConfig(
                    withChainFilePath: Constants.session.ssl.certPfxFile,
                    withPassword: Constants.session.ssl.configPassword,
                    usingSelfSignedCerts: Constants.session.ssl.selfSigning)
#endif

            var signingType = "CA Signed"
            if Constants.session.ssl.selfSigning {
                signingType = "Self-Signed"
            }

            Log.info("Using \(signingType) SSL Certificate")
            Kitura.addHTTPServer(onPort: Constants.session.port, with: serverRoutes.getRoutes(), withSSL: sslConfig)
        }
        else {
            Kitura.addHTTPServer(onPort: Constants.session.port, with: serverRoutes.getRoutes())
        }
        
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
