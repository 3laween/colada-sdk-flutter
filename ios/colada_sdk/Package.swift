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
        .package(name: "FlutterFramework", path: "../FlutterFramework"),
        // The native Colada iOS SDK. This public package carries no source: it
        // declares a binaryTarget pointing at the Colada.xcframework.zip
        // attached to its own GitHub release, which is the same artifact the
        // CocoaPods pod vendors.
        //
        // Pinned exactly, and it must stay in lockstep with `s.dependency
        // 'Colada'` in ../colada_sdk.podspec — a CocoaPods app reads that file
        // and never this one, so the two pins drifting apart would ship
        // different native versions to different hosts.
        .package(url: "https://github.com/3laween/colada-sdk-ios.git", exact: "0.1.1"),
    ],
    targets: [
        .target(
            name: "colada_sdk",
            dependencies: [
                .product(name: "FlutterFramework", package: "FlutterFramework"),
                // Package identity comes from the URL's last path component, so
                // it is "colada-sdk-ios" even though the package and its product
                // are both named "Colada".
                .product(name: "Colada", package: "colada-sdk-ios"),
            ]
        )
    ]
)
