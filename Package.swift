// swift-tools-version:5.0
import PackageDescription

let package = Package(
    name: "Server",
    dependencies: [
        //.package(url: "https://github.com/crspybits/SwiftyAWSSNS.git", .branch("master")),
        .package(url: "https://github.com/crspybits/SwiftyAWSSNS.git", .upToNextMajor(from: "0.3.0")),

        // 7/2/17; See comment in SwiftMain with the same date.
        // .Package(url: "https://github.com/RuntimeTools/SwiftMetrics.git", majorVersion: 1, minor: 2),

        .package(path: "../ServerShared"),
        // .package(url: "../ServerShared", .branch("master")),
        //.package(url: "https://github.com/SyncServerII/ServerShared.git", .branch("master")),
        
        .package(url: "https://github.com/SyncServerII/ServerAccount.git", .branch("master")),

        // .package(url: "../../repos/Perfect-MySQL", .branch("master")),
        // .package(url:"https://github.com/crspybits/Perfect-MySQL.git", from: "3.1.3"),
        .package(url:"https://github.com/PerfectlySoft/Perfect-MySQL.git", .upToNextMajor(from: "3.4.1")),

        .package(url: "https://github.com/PerfectlySoft/Perfect.git", .upToNextMajor(from: "3.1.4")),
        .package(url: "https://github.com/PerfectlySoft/Perfect-Thread.git", .upToNextMajor(from: "3.0.6")),

        .package(url: "https://github.com/IBM-Swift/Kitura.git", .upToNextMajor(from: "2.7.0")),
        
        .package(url: "https://github.com/IBM-Swift/Swift-JWT.git", from: "3.5.3"),
        
        .package(url: "https://github.com/IBM-Swift/Kitura-Credentials.git", .upToNextMajor(from: "2.4.1")),
        .package(url: "https://github.com/IBM-Swift/Kitura-CredentialsFacebook.git", .upToNextMajor(from: "2.3.1")),
        .package(url: "https://github.com/IBM-Swift/Kitura-CredentialsGoogle.git", .upToNextMajor(from: "2.3.1")),
        
        // .package(url: "../../repos/CredentialsDropbox", .branch("master")),
        .package(url: "https://github.com/crspybits/CredentialsDropbox.git", .upToNextMajor(from: "0.4.0")),
        
        // .package(url: "https://github.com/crspybits/CredentialsMicrosoft.git", .branch("master")),
        .package(url: "https://github.com/crspybits/CredentialsMicrosoft.git",  from: "0.1.0"),
        
        .package(url: "https://github.com/crspybits/CredentialsAppleSignIn.git", .branch("master")),
        // .package(url: "https://github.com/crspybits/CredentialsAppleSignIn.git",  from: "0.1.0"),
        
        .package(url: "https://github.com/IBM-Swift/HeliumLogger.git", .upToNextMajor(from: "1.8.1"))
	],
    targets: [
        .target(name: "Main",
            dependencies: ["Server"],
            swiftSettings: [
                .define("DEBUG", .when(platforms: nil, configuration: .debug)),
                .define("SERVER")
            ]),
        .target(name: "Server",
            dependencies: ["ServerShared", "Credentials", "CredentialsGoogle", "PerfectThread", "PerfectMySQL", "HeliumLogger", "CredentialsFacebook", "CredentialsDropbox", "Kitura", "PerfectLib", "SwiftyAWSSNS", "CredentialsMicrosoft", "CredentialsAppleSignIn", "SwiftJWT", "ServerAccount"],
            swiftSettings: [
                .define("DEBUG", .when(platforms: nil, configuration: .debug)),
                .define("SERVER")
            ]),
            
        .testTarget(name: "TestsCommon", dependencies: ["Server", "Main"]),
        
        .testTarget(name: "AccountTests", dependencies: ["TestsCommon"]),
        .testTarget(name: "DatabaseTests", dependencies: ["TestsCommon"]),
        .testTarget(name: "FileControllerTests", dependencies: ["TestsCommon"]),
        .testTarget(name: "SharingTests", dependencies: ["TestsCommon"]),
        .testTarget(name: "AccountFileTests", dependencies: ["TestsCommon"]),
        .testTarget(name: "OtherTests", dependencies: ["TestsCommon"])
    ]
)
