// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PersonalizedHair",
    platforms: [.macOS(.v14), .iOS(.v18)],
    products: [
        .library(name: "HairCore", targets: ["HairCore"]),
        .executable(name: "capture-inspect", targets: ["CaptureInspect"]),
        .executable(name: "processing-probe", targets: ["ProcessingProbe"]),
        .executable(name: "head-photogrammetry", targets: ["HeadPhotogrammetry"])
    ],
    targets: [
        .target(name: "HairCore"),
        .executableTarget(name: "CaptureInspect", dependencies: ["HairCore"]),
        .executableTarget(name: "ProcessingProbe", dependencies: ["HairCore"]),
        .executableTarget(name: "HeadPhotogrammetry", dependencies: ["HairCore"]),
        .testTarget(name: "HairCoreTests", dependencies: ["HairCore"])
    ],
    swiftLanguageModes: [.v5]
)
