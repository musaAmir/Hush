// swift-tools-version: 5.9
import PackageDescription
let package = Package(name: "Hush", platforms: [.macOS(.v14)], dependencies: [
    .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.10.0")
], targets: [
    .target(name: "HushCore"),
    // build.sh copies Sparkle.framework into Contents/Frameworks.
    .executableTarget(name: "Hush", dependencies: ["HushCore", .product(name: "Sparkle", package: "Sparkle")],
                      linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])]),
    .testTarget(name: "HushCoreTests", dependencies: ["HushCore"]),
    .testTarget(name: "HushWindowTests", dependencies: ["Hush"])
])
