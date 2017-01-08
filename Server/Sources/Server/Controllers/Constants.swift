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

protocol ConstantsDelegate {
func plistFilePath(forConstants:Constants) -> String
}

class Constants {
    /* When adding this .plist into your Xcode project make sure to
    a) add it into Copy Files in Build Phases, and 
    b) select Products Directory as a destination.
    For testing, I've had to put a build script in that does:
        cp Server.plist /tmp
    */
    static let serverPlistFile = "Server.plist"
    
    struct mySQL {
        var host:String = ""
        var user:String = ""
        var password:String = ""
        var database:String = ""
    }
    var db = mySQL()
    
    var googleClientId:String = ""
    var googleClientSecret:String = ""

    static var session = Constants()

    // If there is a delegate, then use this to get the plist file path. This is purely a hack for testing-- because I've not been able to get access to the Server.plist file otherwise.
    static var delegate:ConstantsDelegate?
    
    fileprivate init() {
        var plist:PlistDictLoader
        
        if Constants.delegate == nil {
            plist = try! PlistDictLoader(plistFileNameInBundle: Constants.serverPlistFile)
        }
        else {
            let path = Constants.delegate!.plistFilePath(forConstants: self)
            plist = try! PlistDictLoader(usingPath: path, andPlistFileName: Constants.serverPlistFile)
        }
        
        googleClientId = try! plist.getString(varName: "GoogleServerClientId")
        googleClientSecret = try! plist.getString(varName: "GoogleServerSecret")

        db.host = try! plist.getString(varName: "mySQL.host")
        db.user = try! plist.getString(varName: "mySQL.user")
        db.password = try! plist.getString(varName: "mySQL.password")
        db.database = try! plist.getString(varName: "mySQL.database")
    }
}
