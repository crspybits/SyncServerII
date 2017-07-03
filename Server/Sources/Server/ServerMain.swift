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

// 7/2/17; SwiftMetrics, perhaps because it was mis-installed, was causing several of my higher-performing test cases to fail. E.g., 10 consecutive uploads and downloads of a 1MB file. Thus, I've commented it out for now.

// import SwiftMetrics
// import SwiftMetricsDash

// If given, the single command line argument to the server is expected to be a full path to the server config file.

public class ServerMain {
    // If server fails to start, try looking for a process using the port:
    //      sudo lsof -i -n -P | grep TCP | grep 8181
    
    // I'm using port 8181 for local testing, and 443 for AWS.
    // TODO: *1* Using port 443 on the server currently requires that you be root. Is there a way around that?
    
    // static var smd:SwiftMetricsDash?
    
    public enum ServerStartup {
        case blocking // doesn't return from startup (normal case)
        case nonBlocking // returns from startup (for XCTests)
    }
    
    public class func startup(type:ServerStartup = .blocking) {
        Log.logger = HeliumLogger()
        
        Log.info("Launching server in \(type) mode with \(CommandLine.arguments.count) command line arguments.")
        
        // http://www.kitura.io/en/resources/tutorials/swiftmetrics.html
        // https://developer.ibm.com/swift/2017/03/21/using-swiftmetrics-secure-kitura-server/
        // Enable SwiftMetrics Monitoring
        //let sm = try! SwiftMetrics()
        // Pass SwiftMetrics to the dashboard for visualising
        //smd = try? SwiftMetricsDash(swiftMetricsInstance : sm)
        
        if type == .blocking {
            // When we launch the server from within Xcode (or just with no explicit arguments), we have 1 "argument" (CommandLine.arguments[0]).
            if CommandLine.arguments.count == 1 {
                Constants.setup(configFileName: Constants.serverConfigFile)
            }
            else {
                let configFile = CommandLine.arguments[1]
                Log.info("Loading server config file from: \(configFile)")
                Constants.setup(configFileFullPath: configFile)
            }
        }
        
        if !Controllers.setup() {
            Log.error("Failed during startup: Could not setup controller(s).")
            exit(1)
        }
        
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

        let serverRoutes = CreateRoutes()

        Kitura.addHTTPServer(onPort: Constants.session.port, with: serverRoutes.getRoutes(), withSSL: sslConfig)
        
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
