// swift-tools-version:4.0
import PackageDescription

let package = Package(
    name: "Server",
    dependencies: [
        //.package(url: "https://github.com/crspybits/SwiftyAWSSNS.git", .branch("master")),
        .package(url: "https://github.com/crspybits/SwiftyAWSSNS.git", from: "0.2.0"),

        // 7/2/17; See comment in SwiftMain with the same date.
        // .Package(url: "https://github.com/RuntimeTools/SwiftMetrics.git", majorVersion: 1, minor: 2),
        
        // .package(url: "../../repos/CredentialsDropbox", .branch("master")),
        .package(url: "https://github.com/crspybits/CredentialsDropbox.git", from: "0.3.0"),

        // .package(url: "../../repos/SyncServer-Shared", .branch("dev")),
        .package(url: "https://github.com/crspybits/SyncServer-Shared.git", .branch("dev")),
        // .package(url: "https://github.com/crspybits/SyncServer-Shared.git", from: "10.1.0"),

        // .package(url: "../../repos/SMServerLib", .branch("master")),
        .package(url: "https://github.com/crspybits/SMServerLib.git", from: "1.0.0"),

        // .package(url: "../../repos/Perfect-MySQL", .branch("master")),
        // .package(url:"https://github.com/crspybits/Perfect-MySQL.git", from: "3.1.3"),
        .package(url:"https://github.com/PerfectlySoft/Perfect-MySQL.git", from: "3.2.0"),

        .package(url: "https://github.com/PerfectlySoft/Perfect.git", .upToNextMajor(from: "3.1.1")),
        .package(url: "https://github.com/PerfectlySoft/Perfect-Thread.git", .upToNextMajor(from: "3.0.4")),

        .package(url: "https://github.com/IBM-Swift/Kitura.git", .upToNextMajor(from: "2.4.0")),
        
        .package(url: "https://github.com/IBM-Swift/Kitura-Credentials.git", .upToNextMajor(from: "2.2.0")),
        .package(url: "https://github.com/IBM-Swift/Kitura-CredentialsFacebook.git", .upToNextMajor(from: "2.2.0")),
        .package(url: "https://github.com/IBM-Swift/Kitura-CredentialsGoogle.git", .upToNextMajor(from: "2.2.0")),

        .package(url: "https://github.com/IBM-Swift/HeliumLogger.git", .upToNextMajor(from: "1.7.1"))
	],
    targets: [
        .target(name: "Main",
            dependencies: ["Server"]),
        .target(name: "Server",
            dependencies: ["SyncServerShared", "Credentials", "CredentialsGoogle", "SMServerLib", "PerfectThread", "PerfectMySQL", "HeliumLogger", "CredentialsFacebook", "CredentialsDropbox", "Kitura", "PerfectLib", "SwiftyAWSSNS"]),
        .testTarget(name: "ServerTests",
            dependencies: ["Server", "Main", "CredentialsDropbox"])
    ]
)
