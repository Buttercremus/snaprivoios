// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "SnagForgeDomain",
    defaultLocalization: "en",
    platforms: [.macOS(.v26)],
    products: [.library(name: "SnagForgeDomain", targets: ["SnagForgeDomain"])],
    targets: [
        .target(name: "SnagForgeDomain", resources: [.process("Resources")]),
        .testTarget(name: "SnagForgeDomainTests", dependencies: ["SnagForgeDomain"])
    ]
)
