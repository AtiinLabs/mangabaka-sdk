// swift-tools-version: 6.0

import PackageDescription

// Sources/MangaBakaSDK/Generated is produced by swift-openapi-generator from OpenAPI/openapi.json
// and checked in, so apps using the SDK do not build the generator. Regenerate it with
// Scripts/generate.sh, or Scripts/update-openapi.py to also fetch the latest document.
let package = Package(
    name: "mangabaka-sdk",
    platforms: [
        .macOS(.v12), .iOS(.v15)
    ],
    products: [
        .library(name: "MangaBakaSDK", targets: ["MangaBakaSDK"])
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-openapi-runtime", .upToNextMinor(from: "1.13.2")),
        .package(url: "https://github.com/apple/swift-openapi-urlsession", .upToNextMinor(from: "1.3.2")),
        .package(url: "https://github.com/apple/swift-http-types", from: "1.5.1")
    ],
    targets: [
        .target(
            name: "MangaBakaSDK",
            dependencies: [
                .product(name: "HTTPTypes", package: "swift-http-types"),
                .product(name: "OpenAPIRuntime", package: "swift-openapi-runtime"),
                .product(name: "OpenAPIURLSession", package: "swift-openapi-urlsession")
            ]
        ),
        .testTarget(
            name: "MangaBakaSDKTests",
            dependencies: [
                "MangaBakaSDK",
                .product(name: "HTTPTypes", package: "swift-http-types"),
                .product(name: "OpenAPIRuntime", package: "swift-openapi-runtime")
            ]
        )
    ],
    swiftLanguageModes: [.v6]
)
