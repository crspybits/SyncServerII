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

class Constants {
    /* When adding this .plist into your project make sure to
    a) add it into Copy Files in Build Phases, and 
    b) select Products Directory as a destination.
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
    
    fileprivate init() {
        let plist = try! PlistDictLoader(plistFileNameInBundle: Constants.serverPlistFile)

        googleClientId = try! plist.getString(varName: "GoogleServerClientId")
        googleClientSecret = try! plist.getString(varName: "GoogleServerSecret")

        db.host = try! plist.getString(varName: "mySQL.host")
        db.user = try! plist.getString(varName: "mySQL.user")
        db.password = try! plist.getString(varName: "mySQL.password")
        db.database = try! plist.getString(varName: "mySQL.database")
    }
}
