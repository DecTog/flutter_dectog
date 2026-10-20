// swift-tools-version: 5.9
// XCTest for the plugin's Foundation-only Swift, run on the macOS host
// with `swift test --package-path ios/native_tests`. The plugin target itself
// imports Flutter and UIKit, so it cannot build here; Sources/DectogInstall
// holds symlinks to the two production files instead of copies, so the tests
// always compile the shipped code. Not part of the published package
// (.pubignore).
import PackageDescription

let package = Package(
  name: "DectogNativeTests",
  platforms: [.macOS(.v13)],
  targets: [
    .target(name: "DectogInstall", path: "Sources/DectogInstall"),
    .testTarget(name: "DectogInstallTests", dependencies: ["DectogInstall"], path: "Tests/DectogInstallTests"),
  ]
)
