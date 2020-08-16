//
//  Configuration.swift
//  Server
//
//  Created by Christopher G Prince on 9/10/19.
//

// Server startup configuration info.

import LoggerAPI
import Foundation
import PerfectLib

class Configuration {
    let deployedGitTag:String
    
    // The following file is assumed to be at the root of the running, deployed server-- e.g., I'm putting it there when I build the Docker image. File is assumed to contain one line of text.
    private let deployedGitTagFilename = "VERSION"
    
    static private(set) var server: ServerConfiguration!
    static private(set) var misc:Configuration!
#if DEBUG
    static private(set) var test:TestConfiguration?
#endif

    /// testConfigFileFullPath is only for testing, with the DEBUG compilation flag on.
    static func setup(configFileFullPath:String, testConfigFileFullPath:String? = nil) throws {
        misc = try Configuration(configFileFullPath:configFileFullPath, testConfigFileFullPath: testConfigFileFullPath)
    }
    
    private init(configFileFullPath:String, testConfigFileFullPath:String? = nil) throws {
        Log.info("Loading config file: \(configFileFullPath)")

        let decoder = JSONDecoder()

        let url = URL(fileURLWithPath: configFileFullPath)
        let data = try Data(contentsOf: url)
        Configuration.server = try decoder.decode(ServerConfiguration.self, from: data)
        
#if DEBUG
        if let testConfigFileFullPath = testConfigFileFullPath {
            let testConfigUrl = URL(fileURLWithPath: testConfigFileFullPath)
            let testConfigData = try Data(contentsOf: testConfigUrl)
            Configuration.test = try decoder.decode(TestConfiguration.self, from: testConfigData)
        }
#endif
        
        let file = File(deployedGitTagFilename)
        try file.open(.read, permissions: .readUser)
        defer { file.close() }
        let tag = try file.readString()
        
        // In case the line in the file had trailing white space (e.g., a new line)
        self.deployedGitTag = tag.trimmingCharacters(in: NSCharacterSet.whitespacesAndNewlines)
    }
}
