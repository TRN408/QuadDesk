// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "QuadDesk",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "QuadDesk", targets: ["QuadDesk"]),
               .executable(name: "QuadDeskNativePreview", targets: ["QuadDeskNativePreview"]),
               .executable(name: "QuadDisplayWatchdog", targets: ["QuadDisplayWatchdog"])],
    targets: [
        .target(name: "QuadCore"),
        .target(name: "QuadInput"),
        .target(name: "QuadVirtualDisplay", cSettings: [.unsafeFlags(["-fobjc-arc"])],
                linkerSettings: [.linkedFramework("CoreGraphics"), .linkedFramework("Foundation")]),
        .target(name: "QuadDisplayCore"),
        .target(name: "QuadNativeDisplay", dependencies: ["QuadVirtualDisplay", "QuadDisplayCore"]),
        .executableTarget(name: "QuadDeskNativePreview", dependencies: ["QuadNativeDisplay", "QuadVirtualDisplay", "QuadDisplayCore"]),
        .executableTarget(name: "QuadDisplayWatchdog", dependencies: ["QuadDisplayCore"]),
        .executableTarget(name: "QuadDesk", dependencies: ["QuadCore", "QuadInput", "QuadNativeDisplay", "QuadDisplayCore"]),
        .testTarget(name: "QuadCoreTests", dependencies: ["QuadCore"]),
        .testTarget(name: "QuadInputTests", dependencies: ["QuadInput"]),
        .testTarget(name: "QuadDisplayCoreTests", dependencies: ["QuadDisplayCore"]),
        .testTarget(name: "QuadDeskUITests", dependencies: ["QuadDesk", "QuadNativeDisplay"])
    ]
)
