// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "OpenKind",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "OpenKind", targets: ["OpenKindApp"]),
        .executable(name: "OpenKindChecks", targets: ["OpenKindChecks"])
    ],
    targets: [
        .target(name: "OpenKindCore"),
        .executableTarget(name: "OpenKindApp", dependencies: ["OpenKindCore"]),
        .executableTarget(name: "OpenKindChecks", dependencies: ["OpenKindCore"])
    ]
)
