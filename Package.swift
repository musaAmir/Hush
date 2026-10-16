// swift-tools-version: 5.9
import PackageDescription
let package = Package(name: "Hush", platforms: [.macOS(.v14)], targets: [
    .target(name: "HushCore"),
    .executableTarget(name: "Hush", dependencies: ["HushCore"]),
    .testTarget(name: "HushCoreTests", dependencies: ["HushCore"])
])
