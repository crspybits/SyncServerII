// swift-tools-version:4.0
import PackageDescription

let package = Package(
    name: "Server",
    dependencies: [
        // .package(url: "../../repos/CredentialsDropbox", .branch("master")),
        .package(url: "https://github.com/crspybits/CredentialsDropbox.git", .upToNextMinor(from: "0.1.0")),
        
        // .package(url: "../../repos/SyncServer-Shared", .branch("master")),
        .package(url: "https://github.com/crspybits/SyncServer-Shared.git", .upToNextMinor(from: "4.2.0")),

        .package(url: "https://github.com/crspybits/SMServerLib.git", .upToNextMinor(from: "0.0.0")),
        .package(url: "https://github.com/IBM-Swift/Kitura.git", .upToNextMinor(from: "1.7.0")),
        
        // 7/2/17; See comment in SwiftMain with the same date.
        // .Package(url: "https://github.com/RuntimeTools/SwiftMetrics.git", majorVersion: 1, minor: 2),
        
		.package(url: "https://github.com/PerfectlySoft/Perfect.git", .upToNextMinor(from: "2.0.0")),
		.package(url: "https://github.com/PerfectlySoft/Perfect-Thread.git", .upToNextMinor(from: "2.0.0")),

		.package(url:"https://github.com/crspybits/Perfect-MySQL.git", .upToNextMinor(from: "2.1.0")),
		
        // .Package(url: "https://github.com/hkellaway/Gloss.git", majorVersion: 1, minor: 2),
		.package(url: "https://github.com/crspybits/Gloss.git", .upToNextMinor(from: "1.2.0")),
		
        .package(url: "https://github.com/IBM-Swift/Kitura-Credentials.git", .upToNextMinor(from: "1.7.0")),
        .package(url: "https://github.com/IBM-Swift/Kitura-CredentialsFacebook.git", .upToNextMinor(from: "1.7.0")),
        .package(url: "https://github.com/IBM-Swift/Kitura-CredentialsGoogle.git", .upToNextMinor(from: "1.7.0")),

        .package(url: "https://github.com/IBM-Swift/HeliumLogger.git", .upToNextMinor(from: "1.7.0"))
	],
    targets: [
        .target(name: "Main",
            dependencies: ["Server"]),
        .target(name: "Server",
            dependencies: ["SyncServer_Shared", "Kitura-Credentials", "Kitura-CredentialsGoogle", "SMServerLib", "PerfectThread", "MySQL", "HeliumLogger", "Kitura-CredentialsFacebook", "CredentialsDropbox"]),
        .testTarget(name: "ServerTests",
            dependencies: ["Server", "Main", "CredentialsDropbox"])
    ]
)
