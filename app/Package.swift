// swift-tools-version: 6.4
import PackageDescription

let package = Package(
    name: "MultiWorktree",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "MWTKit", targets: ["MWTKit"]),
        .executable(name: "MultiWorktree", targets: ["MultiWorktree"]),
    ],
    targets: [
        .target(name: "MWTKit"),
        .executableTarget(name: "MultiWorktree", dependencies: ["MWTKit"]),
        .executableTarget(name: "MWTDemoSeed", dependencies: ["MWTKit"]),
        .testTarget(name: "MWTKitTests", dependencies: ["MWTKit"]),
        .testTarget(name: "MultiWorktreeTests", dependencies: ["MultiWorktree", "MWTKit"]),
    ]
)
