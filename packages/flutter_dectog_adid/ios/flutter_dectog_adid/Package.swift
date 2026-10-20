// swift-tools-version: 5.9

import PackageDescription

// Swift Package Manager manifest for flutter_dectog_adid. The
// CocoaPods path (../flutter_dectog_adid.podspec) builds the same sources.
// Like flutter_dectog, no package dependency on FlutterFramework: the
// Flutter tool vends the Flutter module through its search paths.
let package = Package(
    name: "flutter_dectog_adid",
    platforms: [
        .iOS("15.0")
    ],
    products: [
        .library(name: "flutter-dectog-adid", targets: ["flutter_dectog_adid"])
    ],
    dependencies: [],
    targets: [
        .target(
            name: "flutter_dectog_adid",
            dependencies: [],
            resources: [
                .process("PrivacyInfo.xcprivacy")
            ],
            linkerSettings: [
                .linkedFramework("AdSupport"),
                .linkedFramework("AppTrackingTransparency"),
            ]
        )
    ]
)
