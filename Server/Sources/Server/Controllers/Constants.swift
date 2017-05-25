//
//  Constants.swift
//  Server
//
//  Created by Christopher Prince on 12/26/16.
//
//

import Foundation
import SMServerLib

// Server-internal constants

// TODO: *1* This should be renamed to something like ServerConfig. They are not exactly "constants".

protocol ConstantsDelegate {
func configFilePath(forConstants:Constants) -> String
}

class Constants {
    /* When adding this .json into your Xcode project make sure to
    a) add it into Copy Files in Build Phases, and 
    b) select Products Directory as a destination.
    For testing, I've had to put a build script in that does:
        cp Server.json /tmp
    */
    static let serverConfigFile = "Server.json"
    
    // TODO: *3* Don't know what this should be
    //static let serverConfigFilePathOnLinux = ""
    
    struct mySQL {
        var host:String = ""
        var user:String = ""
        var password:String = ""
        var database:String = ""
    }
    var db = mySQL()
    
    var googleClientId:String = ""
    var googleClientSecret:String = ""
    var maxNumberDeviceUUIDPerUser:Int?
    
    struct SSL {
        var selfSigning:Bool = false

        // MacOS only. The sslConfigPassword needs to be the "export password:" that comes up in this procedure: https://developer.ibm.com/swift/2016/09/22/securing-kitura-part-1-enabling-ssltls-on-your-swift-server/
        var configPassword:String?
        var certPfxFile:String?
    
        // Linux only.
        var caCertificateDirectory:String?
        var keyFile:String?
        var certFile:String?
    }
    var ssl = SSL()
    
    static var session:Constants!

    // If there is a delegate, then use this to get the config file path. This is purely a hack for testing-- because I've not been able to get access to the Server.config file otherwise.
    static var delegate:ConstantsDelegate?
    
    class func setup(configFileName:String) {
        session = Constants(configFileName:configFileName)
    }
    
    class func setup(configFileFullPath:String) {
        session = Constants(configFileName:configFileFullPath, fileNameHasPath: true)
    }
    
    fileprivate init(configFileName:String, fileNameHasPath:Bool = false) {
        print("loading config file: \(configFileName)")

        var config:ConfigLoader!
        
        if Constants.delegate == nil {
#if os(Linux)
            assert(fileNameHasPath, "Config filename must have path on Linux!")
#endif
            if fileNameHasPath {
                let cfnNSString = NSString(string: configFileName)
                let filename = cfnNSString.lastPathComponent
                let path = cfnNSString.deletingLastPathComponent
                config = try! ConfigLoader(usingPath: path, andFileName: filename, forConfigType: .jsonDictionary)
            }
            
#if os(macOS)
            if !fileNameHasPath {
                config = try! ConfigLoader(fileNameInBundle: configFileName, forConfigType: .jsonDictionary)
            }
#endif
        }
        else {
            let path = Constants.delegate!.configFilePath(forConstants: self)
            config = try! ConfigLoader(usingPath: path, andFileName: configFileName, forConfigType: .jsonDictionary)
        }
        
        googleClientId = try! config.getString(varName: "GoogleServerClientId")
        googleClientSecret = try! config.getString(varName: "GoogleServerSecret")

        db.host = try! config.getString(varName: "mySQL.host")
        db.user = try! config.getString(varName: "mySQL.user")
        db.password = try! config.getString(varName: "mySQL.password")
        db.database = try! config.getString(varName: "mySQL.database")
        
        maxNumberDeviceUUIDPerUser = try? config.getInt(varName: "maxNumberDeviceUUIDPerUser")
        print("maxNumberDeviceUUIDPerUser: \(String(describing: maxNumberDeviceUUIDPerUser))")
        
        // TODO: *3* Make a getBool method.
        if let selfSigning = try? config.getString(varName: "ssl.selfSigning"), selfSigning == "true" {
            ssl.selfSigning = true
        }
        
        // MacOS
        ssl.configPassword = try? config.getString(varName: "ssl.configPassword")
        ssl.certPfxFile = try? config.getString(varName: "ssl.certPfxFile")

        // Linux
        ssl.keyFile = try? config.getString(varName: "ssl.keyFile")
        ssl.certFile = try? config.getString(varName: "ssl.certFile")
        ssl.caCertificateDirectory = try? config.getString(varName: "ssl.caCertificateDirectory")
    }
}
