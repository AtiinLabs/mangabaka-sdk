// swift-tools-version: 6.0

// Builds swift-openapi-generator for Scripts/generate.sh. Not part of the MangaBakaSDK package:
// the generated client is checked in, so consumers do not depend on the generator.

import PackageDescription

let package = Package(
    name: "Generator",
    platforms: [.macOS(.v13)],
    dependencies: [
        .package(url: "https://github.com/apple/swift-openapi-generator", exact: "1.14.2")
    ]
)
