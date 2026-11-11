// swift-tools-version: 5.9
// XCTest for the plugin's Foundation-only Swift, run on the macOS host
// with `swift test --package-path ios/native_tests`. The plugin target itself
// imports Flutter and UIKit, so it cannot build here; Sources/AdtoInstall
// holds symlinks to the two production files instead of copies, so the tests
// always compile the shipped code. Not part of the published package
// (.pubignore).
import PackageDescription

let package = Package(
  name: "AdtoNativeTests",
  platforms: [.macOS(.v13)],
  targets: [
    .target(name: "AdtoInstall", path: "Sources/AdtoInstall"),
    .testTarget(name: "AdtoInstallTests", dependencies: ["AdtoInstall"], path: "Tests/AdtoInstallTests"),
  ]
)
