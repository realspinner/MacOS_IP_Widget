// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "IPWidget",
    platforms: [
        .macOS("26.0")
    ],
    products: [
        .library(name: "IPWidgetCore", targets: ["IPWidgetCore"]),
        .library(name: "IPWidgetUI", targets: ["IPWidgetUI"]),
        .executable(name: "IPWidgetApp", targets: ["IPWidgetApp"]),
        .executable(name: "IPWidgetSnapshot", targets: ["IPWidgetSnapshot"]),
    ],
    targets: [
        .target(
            name: "IPWidgetCore",
            resources: [.copy("Resources")],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .target(
            name: "IPWidgetUI",
            dependencies: ["IPWidgetCore"],
            swiftSettings: [.swiftLanguageMode(.v6)],
            linkerSettings: [.linkedFramework("WidgetKit")]
        ),
        .executableTarget(
            name: "IPWidgetApp",
            dependencies: ["IPWidgetCore", "IPWidgetUI"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .executableTarget(
            name: "IPWidgetSnapshot",
            dependencies: ["IPWidgetCore", "IPWidgetUI"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "IPWidgetCoreTests",
            dependencies: ["IPWidgetCore"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
    ]
)
