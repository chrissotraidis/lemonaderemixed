// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "LemonadeRemixed",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "RemixCore", path: "Sources/RemixCore"),
        .executableTarget(name: "LemonadeRemixed", dependencies: ["RemixCore"], path: "Sources/LemonadeRemixed"),
        .executableTarget(name: "remix-unpack", dependencies: ["RemixCore"], path: "Sources/remix-unpack"),
    ]
)
