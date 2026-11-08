// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CIAKit",
    platforms: [.macOS(.v14), .iOS("26.0")],
    products: [.library(name: "CIAKit", targets: ["CIAKit"]), .executable(name: "cia-convert", targets: ["CIAConvert"])],
    targets: [
        .target(name: "CCrypto"),
        .target(name: "CIAKit", dependencies: ["CCrypto"]),
        .executableTarget(name: "CIAConvert", dependencies: ["CIAKit"]),
        .testTarget(name: "CIAKitTests", dependencies: ["CIAKit"])
    ]
)
