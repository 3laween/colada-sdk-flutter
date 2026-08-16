// swift-tools-version: 5.9
import PackageDescription

// Swift Package Manager manifest for the Colada Flutter plugin's iOS side.
//
// This exists ALONGSIDE ios/colada_sdk.podspec, not instead of it: an app using
// CocoaPods reads the podspec, an app using Swift Package Manager reads this,
// and both compile the same sources under Sources/colada_sdk/. Flutter is
// migrating its default to Swift Package Manager and warns about plugins that
// ship only a podspec, so shipping only one would eventually leave a set of
// host apps unable to link this plugin at all.
let package = Package(
    name: "colada_sdk",
    platforms: [
        // Matches the native Colada iOS SDK's own floor.
        .iOS("13.0")
    ],
    products: [
        .library(name: "colada-sdk", targets: ["colada_sdk"])
    ],
    dependencies: [
        .package(name: "FlutterFramework", path: "../FlutterFramework")
    ],
    targets: [
        .target(
            name: "colada_sdk",
            dependencies: [
                .product(name: "FlutterFramework", package: "FlutterFramework")
            ]
            // The native Colada iOS SDK dependency is added in Phase 9. It is
            // published both as the CocoaPods pod `Colada` and as the public
            // Swift package github.com/3laween/colada-sdk-ios, so both this
            // manifest and the podspec have something to point at.
        )
    ]
)
