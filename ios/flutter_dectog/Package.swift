// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

// Swift Package Manager manifest for the flutter_dectog iOS plugin.
// Flutter 3.44+ resolves plugins through SwiftPM by default and falls back to
// CocoaPods only for plugins without a manifest; ../flutter_dectog.podspec
// keeps the CocoaPods path working for hosts that disabled SwiftPM. Both
// build from the same sources under Sources/flutter_dectog.
//
// No package dependency on FlutterFramework on purpose: the Flutter tool
// vends the Flutter module to plugin packages through its generated package
// and framework search paths (device_info_plus, package_info_plus and
// connectivity_plus ship this way), and a manifest that depends on
// `../FlutterFramework` only resolves inside the tool's generated package
// directory — the example app's Xcode project also references this package
// at its real path, which broke CocoaPods-mode builds and would pin hosts to
// Flutter ≥ 3.44.
let package = Package(
    name: "flutter_dectog",
    platforms: [
        .iOS("15.0")
    ],
    products: [
        // Plugin names with "_" use "-" for the library name (Flutter convention).
        .library(name: "flutter-dectog", targets: ["flutter_dectog"])
    ],
    dependencies: [],
    targets: [
        .target(
            name: "flutter_dectog",
            dependencies: [],
            resources: [
                // Apple privacy manifest: required-reason file-timestamp API
                // (install dates) and the collected-data declarations.
                .process("PrivacyInfo.xcprivacy")
            ],
            linkerSettings: [
                // Apple Search Ads attribution token (AAAttribution, iOS 14.3+);
                // the Swift side guards with canImport + #available and
                // returns nil on the simulator.
                .linkedFramework("AdServices")
            ]
        )
    ]
)
